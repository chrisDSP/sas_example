/*SASIOTEST Console Output Parser*/
/**/
/*Program by: Chris Vincent 		Date: 09/21/2016*/

/*This SAS program compliments the sasiotest_application.ps1 Powershell script I wrote and relies on file names created by that script.*/

/*INPUT DATASETS: */
/*	NONE. Only the path to the SASIOTEST console output files are required. Specify a full path in the pathtologs macro var.*/
/*OUPUT DATASETS: */
/*	The warehouse dataset is defined by the macro vars outputlib.outputmem.  */
/*		This program will create this dataset if it does not exist, otherwise it will append to it. */

%let outputlib = VA; 
%let outputmem = network_outage_wh;

%let pathtologs = "N:\SASIOTEST Logs";

%macro init_ETL;

/*	filename logfiles pipe "dir "&pathtologs."";*/
	/*the above filename assignment above only works for local files and mapped network drives.
		use the filename assignment command below to process files in a remote path.*/
	filename logfiles pipe "pushd "&pathtologs." & dir";
	
	/*QUICK TEST TO SEE IF THE COMMAND WAS PIPED SUCCESSFULLY*/
/*	DATA TESTOUTPUT;*/
/*		INFILE logfiles LRECL=512 TRUNCOVER;*/
/*		INPUT LINE $512.;*/
/*		RUN;*/

	/*pull in all output files from scheduled server and workstation runs of SASIOTEST*/

	data dirlist;
		infile logfiles lrecl=512 truncover;                          
		input line $512.;                                            
		length file_name $ 256;                                      
		file_name="&pathtologs."||compress(substr(line,39),' ');
		short_file = compress(substr(line,39),' ');
		timestamps = substr(line,1,20); 
		drop line; 
		if substr(file_name,75,7) ne "IO_test" then delete;
	RUN; 

	/*pull all file ID hashes from the log warehouse, but only if the warehouse presently exists.*/
	%global file_ids;
	%if %sysfunc(exist(&outputlib..&outputmem.)) %then 
		%do;
			proc sql noprint;
				select distinct quote(file_id) as file_ids into :file_ids separated by ' ' from &outputlib..&outputmem.;
			quit;
		%end;
		%else %do;
				%let file_ids = 'NO WAREHOUSE';
	%end;
%mend;

%init_ETL;
	/*make macro variables for all log files to be processed. 
		only process log files whose file IDs aren't already in the warehouse.*/
	data _null_;  
		set dirlist end=end;                                         
		count+1;
		call symput('read'||left(count),quote(compress(file_name,' ','t')));      
		call symput('dset'||left(count),"logfile_"||strip(count));  
		call symput('filetime'||left(count),compress(timestamps,' ','t'));    
		if end then call symput('max',strip(count));
		where put(md5(compress(file_name,' ','t')), $hex32.) not in (&file_ids.); 
	run;

	/*begin the main processing macro. the loop contained within the macro processes one log file per iteration.  
		friendly progress information is output to the SAS log.
		the all_logs dataset is created, then appended with each iteration.*/



%macro READIN;

	%do i=1 %to &max.;  


		%PUT THIS IS READ &i.: &&read&i.. END;
		%PUT THIS IS DSET &i.: &&dset&i.. END; 
		%PUT THERE ARE &max. LOG FILES TO PROCESS;
		 
		                             
		data readin;
			length line $ 4096
				   filename $ 256;
			infile &&read&i..  TERMSTR="!" DELIMITER="*" lrecl=32767;
			input line $;
			time = "&&filetime&i..";
			filename = &&read&i..;
		run;
			

		data &&dset&i (drop=line i speed regex:);
			format timestamp datetime7.
				   runtime time11.
				   runday mmddyy10.
				   speed_num 13.6
				   machine_name $char40.
				   user_id $char12.;
			set readin;
			if _n_=1 then 
				do;
					retain  regex_operation_type regex_speed regex_pagesize regex_filesize;

					regex_operation_type = prxparse('/pagesize\.\s*(\S+)\sThroughput/');
					regex_speed = prxparse('/Throughput:\s(\S+)\sMB/');
					regex_pagesize = prxparse('/a\s(\d+)\spagesize/');
					regex_filesize = prxparse('/ing\s(\d+)\sbytes/');

				end;

			array expressions {*} regex:;
			array out_fields {*} $ 64 operation_type speed pagesize filesize;
			do i=1 to dim(out_fields);
				if prxmatch(expressions{i}, line) then 
					do;
						out_fields{i}= upcase(prxposn(expressions{i}, 1, line));
					end;		
			end;
			
			machine_name = scan(filename, -3, "_");
			user_id = scan(filename, -2, "_");
			speed_num = input(speed, 13.6);
			runday = input(substr(time,1,10), mmddyy10.);
			runtime = input(substr(time,13,8), time11.);
			timestamp = dhms(runday, 0, 0, runtime);
			file_id = put(md5(&&read&i..), $hex32.);
		run;
						


		%if &i.=1 %then 
			%do;
				data all_logs;
					set &&dset&i;					
				run;
			%end;
		%else %do;
			proc append base=all_logs data=&&dset&i;
			where time is not missing;
			run;
		%end;

		proc datasets noprint library=work;
			delete &&dset&i readin;
		quit;

	%end;     

%mend;                                                
                                                             
%READIN;    

/*look to see if a log warehouse dataset has been established in the destination. if not, create one. 
	if the warehouse dataset is present, append to it.*/

%macro WHLOGS;

	%if %sysfunc(exist(&outputlib..&outputmem.)) %then 
		%do;

		proc append base=&outputlib..&outputmem. data=all_logs;
		run;
		%end;
	%else %do;
		data &outputlib..&outputmem.;
			set all_logs;
		run;
		%end;
	proc datasets noprint library=work;
		delete all_logs dirlist;
	quit;

%mend;

%whlogs;