# sas_example

Use the powershell script sasiotest_application.ps1 to call 
the SAS Intstitute's SASIOTEST.exe utility in order to test sequential write performance on a network drive or disk array.


Run the ETL_NETWORK_PROBLEMS.sas SAS program to parse in the raw text logfiles created by the powershell script.
This create a dataset with one timestamped row per SASIOTEST run. 

Schedule the script to run in Windows task scheduler at a regular interval (eg., daily or hourly) to develop a performance 
profile of a target network drive or disk array. 
