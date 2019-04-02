#!/usr/bin/perl
#Call Alma APIs to scan a file of barcodes out of Transit or out of a Work Order Department
#

use LWP::UserAgent;
use XML::Simple;
use Data::Dumper;
#Need secure FTP for file transfer from bonnet
use Net::SFTP::Foreign;    # Secure FTP
use IO::Pty;
use MIME::Lite;

#Get today's date
($my_day, $my_mon, $my_year) = (localtime) [3,4,5];
$my_year += 1900;
$my_mon += 1;
$my_date = sprintf("%s%02d%02d", $my_year, $my_mon, $my_day);

$out_log = sprintf("%s%s%s", "scan_in_items_", $my_date, ".log");

$ret = open(OUT_LOG, ">$out_log");
if ($ret < 1)
{
     fatal_failure("Cannot open log file $out_log");
}

$no_errors = $no_proc = 0;

#For testing or reloading set to 1
#If skipping FTP need to set in_fn to csv file sitting on the server
$skip_ftp = 1;
$in_fn = "test_barcodes.csv";


if (!$skip_ftp)
{ 
     #FTP files from server
     if ($sftp = Net::SFTP::Foreign->new("someserver.bc.edu", user => 'some_username', password => 'some_password', port => '22'))
     {
          if ($sftp->setcwd("alma/some_directory"))
	  {
               @ps_files = @{$sftp->ls('.', names_only => 1) };
               $no_files = @ps_files;
               for ($i = 0; $i < $no_files; $i++)
               {
	            $in_fn = $ps_files[$i];

                    @file_pts = split(/\./, $in_fn); #Ensure this is a CSV file before processing it 

                    if ($file_pts[1] eq 'csv' || $file_pts[1] eq 'CSV') 
                    {
                         if ($sftp->get($in_fn, $in_fn)) #Get the file from bonnet
                         {    
			      $no_errors = $no_proc = 0;
			      &process_file($in_fn);     #Process the file
                              $line_out = sprintf("%s%s", "File processed: ", $in_fn);
                              print OUT_LOG ("$line_out\n");
                              $line_out = sprintf("%s%s", "Number of records successfully processed: ", $no_proc);
                              print OUT_LOG ("$line_out\n");
                              $line_out = sprintf("%s%s", "Number of records with errors: ", $no_errors);
                              print OUT_LOG ("$line_out\n");
                              $sftp->remove($in_fn);     #Delete the file from server
                         }
                    }
               }
          }
     }

}
elsif ($in_fn) 
{
     &process_file($in_fn);
     $line_out = sprintf("%s%s", "File processed: ", $in_fn);
     print OUT_LOG ("$line_out\n");
     $line_out = sprintf("%s%s", "Number of records successfully processed: ", $no_proc);
     print OUT_LOG ("$line_out\n");
     $line_out = sprintf("%s%s", "Number of records with errors: ", $no_errors);
     print OUT_LOG ("$line_out\n");
}

close (OUT_LOG);                     #Close the log so everything in the pipe gets written
&send_log($out_log, $in_fn);         #Email the log

exit;

sub process_file
{

     $library = 'ONL';  #Library Code if scanning items out of transit
     $circ_desk = 'DEFAULT_CIRC_DESK'; #Returns circulation desk code if scanning items out of transit
     $department = 'DIGITIZATION'; #Work order department code if scanning items out of work order department

     #API key
     $api_key = "YOUR_API_KEY_GOES_HERE"; 

     #ExLibris API call
     $item_base = "https://api-na.hosted.exlibrisgroup.com/almaws/v1/items?item_barcode=";
     $itemkey_add = "&apikey=";
     $bib_base = "https://api-na.hosted.exlibrisgroup.com/almaws/v1/bibs/";
     $bib_add = "/holdings/?apikey=";
     $hold_add = "/holdings/";
     $scankey_add = "?apikey=";
     $item_add = "/items/";

     my ($in_fn) = @_;

     $line_out = sprintf("%s%s", "Processing file: ", $in_fn);
     print OUT_LOG ("$line_out\n");


     #Open the file
     $ret = open(FILE_IN, $in_fn);
     if ($ret < 1)
     {
          $line_out = sprintf("%s%s%", "Unable to open input file: ", $in_fn);
          print OUT_LOG ("$line_out\n");
          return;
     }

     #Open API calling agents - one for get, one for post, not sure if I need both or not
     $item_call = LWP::UserAgent->new(
         ssl_opts => { verify_hostname => 0 },
         cookie_jar => {},
     );

     $scanin_call = LWP::UserAgent->new(
         ssl_opts => { verify_hostname => 0 },
         cookie_jar => {},
     );



     $my_line = <FILE_IN>; #Grab first line in file

     while ($my_line ne "")
     {
	  $barcode = $my_line;
          #Remove the junk like possible line feed at end of string
          $barcode =~ s/^\s+|\s+$//g;

          #Call item API with barcode to retrieve the MMS ID, holding ID and item ID for this item
          $item_url = sprintf("%s%s%s%s", $item_base, $barcode, $itemkey_add, $api_key);
          $item_resp = $item_call->get($item_url);
          $item_xml = XMLin($item_resp->content, ForceArray=>1, KeyAttr=>undef);
          if ($item_resp->is_success)
          {
               #print Dumper($item_xml);

               $hold_id = $item_xml->{holding_data}->[0]->{holding_id}->[0];
               $item_id = $item_xml->{item_data}->[0]->{pid}->[0];
               $mms_id = $item_xml->{bib_data}->[0]->{mms_id}->[0];
               
               #add_ops Line to use if scanning in an item from in-transit. Set library and circ desk to owning library code and return circ desk code
               #$add_ops = "&op=scan&library=$library&circ_desk=$circ_desk";

               #add_ops line to use if scanning an item out of a work order department and back on shelf
               #Set done=true to indicate work order processing is completed on the item.
               $add_ops = "&op=scan&external_id=false&department=$department&done=true&auto_print_slip=false&place_on_hold_shelf=false&confirm=false";
               $scanin_url = sprintf("%s%s%s%s%s%s%s%s%s", $bib_base, $mms_id, $hold_add, $hold_id, $item_add, $item_id, $scankey_add, $api_key, $add_ops);

               $scanin_req = HTTP::Request->new( POST => "$scanin_url");
               $scanin_req->content_type('application/xml');
               $result = $scanin_call->request( $scanin_req );


               if ($result->is_success) #Successful Scan from WOD
               {
                    #print Dumper ($result);
		    $no_proc++;
               }
               else
               {
                    #Error scanning in item
		    my ($errM) = ( $result->content =~ m{<errorMessage>(.*?)</errorMessage>}msi );

	            $line_out = sprintf("%s%s%s%s%s%s%s%s%s%s%s", "Error scanning in item: ", "Barcode=", $barcode, " MMS ID=", $mms_id, " Item ID=", $item_id, " Holding ID=", $hold_id, " Error: ", $errM);
                    print OUT_LOG ("$line_out\n\n");
                    $no_errors++;
               }
	  }
          else 
          {
               #Error in full get
	       $line_out = sprintf("%s%s%s", "Error retrieving full item information for the following: ", "Barcode= ", $barcode);
               print OUT_LOG ("$line_out\n");
               $no_errors++;

          }

          $my_line = <FILE_IN>; #Grab next line in the file

     }

     return;
}


sub send_log
{
     my($log, $in_fn) = @_;

     $i = 0;
     @log_lines;

     $email_sender = "Boston College Library";
     $recipient = "briandwo\@bc.edu";

     $email_subject = "File(s) processed to scan in items";

     #Open the output log 
     $ret = open(LOG_IN, $log);
     if ($ret < 1)
     {
         fatal_failure("Cannot open log file $log");
     }

     $my_line = <LOG_IN>; 

     while ($my_line ne "")
     {
          $log_lines[$i] = $my_line;
          $i++;
          $my_line = <LOG_IN>; 
     }

     $msg = MIME::Lite->new(
                           From => "$email_sender",
                           To => "$recipient",
                           Subject => "$email_subject",
                           Datestamp => 'true',
                           Date => "",
                           Data => "@log_lines"
                           );
     $msg->send;

     close (LOG_IN);

     return;

}


