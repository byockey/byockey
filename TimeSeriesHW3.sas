libname hw3 '/gpfs/user_home/os_home_dirs/byockey/Bryan Yockey/Time_Series/HW3';

/* FILENAME REFFILE '/gpfs/user_home/os_home_dirs/byockey/Bryan Yockey/Time_Series/HW3/Assignment 3 Data.xlsx'; */
/*  */
/* PROC IMPORT DATAFILE=REFFILE */
/* 	DBMS=XLSX */
/* 	OUT=hw3.data; */
/* 	GETNAMES=YES; */
/* RUN; */

*Moving data to the work library and splitting it into a single dataset per question;
%macro split(data= , keep= ,screen=);
	data work;
		set hw3.data;
	run;
	data &data;
		set work;
		keep &keep;
		if &screen = . then delete;
	run;
%mend split;

%split(data= sealevel, keep=year month "Sea Level"n, screen= year);
%split(data= sales, keep=year1 month1 sales, screen= year1);
%split(data= credit, keep=year2 month2 credit, screen= year2);
%split(data= price, keep=year1 month1 price, screen= year1);	
************************************************************************************************************************
*                                            			1a                                                             *
***********************************************************************************************************************;
*Spliting data for model building and forecast validation;
data train_sales test_sales;
	set sales;
		if year1 le 2009 then output train_sales;
		if year1 = 2010 then output test_sales;
run;

*looking at the raw data;
proc arima data=train_sales;
	identify var=sales;
run;

*box cox tranformation;
data train_sales_boxcox;
	set train_sales;
	x=0;
	proc transreg  maxiter=0  nozeroconstant;
	model boxcox(sales)=identity(x);
	output;
run;

*Log transformation;
Data train_sales_trans;
	set train_sales;
	log_sales=log(sales);
run;

*Fitting a model for sales;
proc arima data=train_sales_trans;
	identify var=log_sales;
run;

*There is a trend here that needs to be addressed with differencing;
proc arima data=train_sales_trans;
	identify var=log_sales(1);
run;

*This series has a seasonal component based on the ACF Plot. It seem to need a 6 month seasonal differencing.;

proc arima data=train_sales;
	identify var=sales(12);
run;
* This is much better. I want to look at a variogram to assess the stationarity;
proc arima data=train_sales_trans;
	identify var=log_sales(12) outcov=covs nlag=75;
	run;	
data vario;
	set covs;
	retain corrlag1;
	if lag = 1 then corrlag1=corr;
	variogram=(1-corr)/(1-corrlag1);
run;
proc sgplot data=vario;
	series x=lag y=variogram;
run;
*I want to look at the SCAN MINIC and ESACF to find estimates for p and q;
proc arima data= train_sales_trans;
	identify var= log_sales(12) SCAN MINIC ESACF;
run;

proc arima data= train_sales_trans;
	identify var= log_sales(12);
/* 	estimate p= (1 2 12) q=(1) noint; */
/* 	estimate p= (12) q=3 noint; */
	estimate p= (1 2) q=(1) (12) noint;
/* 	estimate p=1 q=(1 2) (12) noint; */
run;
*forecast for second and compare;
************************************************************************************************************************
*                                            			1b                                                             *
***********************************************************************************************************************;
*Forecasting sales;

*I want to compare forecasts;
proc arima data= train_sales_trans;
	identify var= log_sales(12);
	estimate p= (1 2) q=(1) (12) noint;
	forecast lead= 7 out= sales_two_one;
	estimate p=1 q=(1 2) (12) noint;
	forecast lead= 7 out= sales_one_two;
run;

data sales_tranfored_forecast_a;
	set sales_two_one;
	where log_sales = .;
	l95 = exp( l95 );
	u95 = exp( u95 );
	forecast = exp( forecast + std*std/2 );
	month= _n_;
run;

data sales_tranfored_forecast_b;
	set sales_one_two;
	where log_sales = .;
	l95 = exp( l95 );
	u95 = exp( u95 );
	forecast = exp( forecast + std*std/2 );
	month= _n_;
run;

proc print data=sales_tranfored_forecast;
run;

PROC SQL;
	CREATE TABLE sales_comparison AS 
	SELECT b.sales AS "Actual Sales"n, a.forecast format= 10. AS "ARIMA(2,1)Forecasted Sales"n , c.forecast format=10. AS "ARIMA(1,2)Forcasted Sales"n
	FROM sales_tranfored_forecast_a AS a inner join test_sales AS b 
	ON a.month = b.month1 
	inner join sales_tranfored_forecast_b AS c
	on b.month1=c.month;
quit;

Proc PRint data= sales_comparison;
run;

data model_pick;
	set sales_comparison;
	"difference ARIMA(2,1)"n =abs("ARIMA(2,1)Forecasted Sales"n-"Actual Sales"n);
	"difference ARIMA(1,2)"n =abs("ARIMA(1,2)Forcasted Sales"n-"Actual Sales"n);
	step1_a= "difference ARIMA(2,1)"n/"Actual Sales"n;
	step1_b= "difference ARIMA(1,2)"n/"Actual Sales"n;
run;

Proc sql;
	CREATE TABLE mad AS
	SELECT sum("difference ARIMA(2,1)"n)/7 AS "MAD for ARMA(2,1)"n,
		   sum("difference ARIMA(1,2)"n)/7 AS "MAD for ARMA(1,2)"n,
		   sum(step1_a)/7 AS "MAPD for ARMA(2,1)"n,
		   sum(step1_b)/7 AS "MAPD for ARMA(1,2)"n
	FROM model_pick;
quit;

proc print data=mad;
run;
	
************************************************************************************************************************
*                                            			2a                                                             *
***********************************************************************************************************************;
*Spliting data for model building and forecast validation;
data train_price test_price;
	set price;
		if year1 le 2009 then output train_price;
		if year1 =2010 then output test_price;
run;

*Fitting a model for price;
proc arima data=train_price;
	identify var=price;
run;

*adjusting for season;
proc arima data=train_price;
	identify var=price(12);
run;

*There is still an issue with stationarity differencing once nonseasonally;
proc arima data=train_price;
	identify var=price(12 1);
run;

*This looks much better there might be an issue with the variance. I am 
checking this with a variogram;
proc arima data=train_price;
	identify var=price(12 1) outcov=covs nlag=75;
	run;	
data vario;
	set covs;
	retain corrlag1;
	if lag = 1 then corrlag1=corr;
	variogram=(1-corr)/(1-corrlag1);
run;
proc sgplot data=vario;
	series x=lag y=variogram;
run;
*This looks much better;

*Finding p and q for once differenced, seasonal data;
proc arima data=train_price;
	identify var=price(12 1) SCAN MINIC ESACF nlag=50;
run;

*The ACF seems to cut off after the first seasonal lag and the PACF seasonal lags seem to decay.
This means I need a seasonal MA(1);

*From SCAN MINIC ESACF I am going to try 2,0 1,2 1,1 2,1

*Estimating the suggestions of SCAN MINIC and ESACF;
proc arima data=train_price;
	identify var=price(12 1);
/* 	estimate p=2 q= (12) noint; */
/* 	estimate p=1 q= (1 2) (12) noint; */
/* 	estimate p=1 q=(1) (12) noint; */
	estimate p=2 q=(1) (12) noint;
run;

*ARIMA(2,1,1)x(0,1,1)12  Seems to be the best, all terms are significant and the residual histogram looks the best from
these options;

	
************************************************************************************************************************
*                                            			2b                                                             *
***********************************************************************************************************************;
*Forecasting price;
Proc arima data= train_price out= price_forecast;
	identify var= price(12 1);
	estimate p=2 q=(1) (12) noint;
	forecast lead= 7 id= month1 out=price_cast;
run;

data price_forecast;
	set price_cast;
	where price = .;
	month =_n_;
run;

PROC SQL;
	CREATE TABLE price_comparison AS 
	SELECT a.forecast AS "Forecasted Price"n , b.price AS "Actual Price"n
	FROM price_forecast AS a inner join test_price AS b
	ON a.month = b.month1;
quit;

proc print data= price_comparison;
run;

************************************************************************************************************************
*                                            			3a                                                             *
***********************************************************************************************************************;
*First I need to add the missing observations to the credit data;
data extra;
	input Year2  Month2 $3. Credit;
	datalines;
		2010 Mar 1161466
		2010 Apr 1157648
		2010 May 1152223
		2010 Jun 1148219
		2010 Jul 1147999
		2010 Aug 1143622
		;
run;

proc append base= credit
	data= extra;
run;

*Spliting data for model building and forecast validation;
data train_credit test_credit;
	set credit;
		if year2 le 2009 then output train_credit;
		if year2 =2010 then output test_credit;
run;

*Fitting a model for credit;
proc arima data=train_credit;
	identify var=credit;
run;

proc arima data=train_credit;
	identify var=credit(12 1);
run;

*Need a transformation;
data train_credit_boxcox;
	set train_credit;
	x=0;
	proc transreg  maxiter=0  nozeroconstant;
	model boxcox(credit)=identity(x);
	output;
run;

*square root transformation;
Data train_credit_trans;
	set train_credit;
	trans_credit=credit**.25;
run;

proc arima data=train_credit_trans;
	identify var=trans_credit;
run;

proc arima data=train_credit_trans;
	identify var=trans_credit(12 1);
run;

proc arima data=train_credit_trans;
	identify var=trans_credit(12 1) SCAN MINIC ESACF;
run;

proc arima data=train_credit_trans;
	identify var=trans_credit(12 1);
	estimate p= 1 q=(1) (12) noint;
run;
************************************************************************************************************************
*                                            			3b                                                             *
***********************************************************************************************************************;
*Forecasting credit;
Proc arima data= train_credit_trans;
	identify var= trans_credit(12 1);
	estimate p= (1) q=(1) (12) noint;
	forecast lead= 8 out=credit_forecast;
run;

data credit_tranfored_forecast;
	set credit_forecast;
	where trans_credit = .;
	l95 = l95**4 ;
	u95 = u95**4;
	forecast =( forecast + std*std/2 )**4;
	month=_n_;
run;

data test_credit_month;
	set test_credit;
	month=_n_;
run;

PROC SQL;
	CREATE TABLE credit_comparison AS 
	SELECT a.forecast format= 10. AS "Forecasted Credit"n , b.credit AS "Actual Credit"n
	FROM credit_tranfored_forecast AS a inner join test_credit_month AS b
	ON a.month = b.month;
quit;

Proc PRint data= credit_comparison;
run;

************************************************************************************************************************
*                                            			4                                                              *
***********************************************************************************************************************;
*Fitting a model for sea level;
proc arima data=sealevel;
	identify var="Sea Level"n;
run;
*There is a seasonal componet that needs to be addressed;

proc arima data=sealevel;
	identify var="Sea Level"n(12 1);
run;
*This looks much better. I need to check that the variance is ok;

proc arima data=sealevel ;
	identify var="Sea Level"n(12 1) outcov=covs nlag=75;
run;
data vario;
	set covs;
	retain corrlag1;
	if lag = 1 then corrlag1=corr;
	variogram=(1-corr)/(1-corrlag1);
run;
proc sgplot data=vario;
	series x=lag y=variogram;
run;
*The variogram shows that the process is stationary;

proc arima data=sealevel ;
	identify var="Sea Level"n(12 1) SCAN MINIC ESACF;
run;

proc arima data=sealevel;
	identify var="Sea Level"n(12 1);
/* 	estimate q=(1)(12) noint; */
/* 	estimate p=(1) q=(1) (12) noint; */
	estimate q=(1 4)(12) noint;
run;



