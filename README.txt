This PERL code reads a .csv file of barcodes. For each barcode read an Alma API is called with the barcode as an input parameter and the corresponding MMS ID, Holding ID and Item ID is returned. The MMS ID, Holding ID and Item ID are then used to call the Alma scan-in items API. The scan-in items API can be used to scan items out of transit or to scan items out of a work order department. 

For help on getting an API key from Ex Libris please refer to: https://developers.exlibrisgroup.com/alma/apis. 

For documentation on how to use a barcode to retrieve the MMS ID, Holding ID and Item ID please refer to: https://developers.exlibrisgroup.com/alma/apis/docs/bibs/R0VUIC9hbG1hd3MvdjEvYmlicy97bW1zX2lkfS9ob2xkaW5ncy97aG9sZGluZ19pZH0vaXRlbXMve2l0ZW1fcGlkfQ==/ and read the Note. 

For help on calling the scan-in items API please refer to: https://developers.exlibrisgroup.com/alma/apis/docs/bibs/UE9TVCAvYWxtYXdzL3YxL2JpYnMve21tc19pZH0vaG9sZGluZ3Mve2hvbGRpbmdfaWR9L2l0ZW1zL3tpdGVtX3BpZH0=/

