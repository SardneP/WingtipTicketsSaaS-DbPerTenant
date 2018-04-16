<#
.SYNOPSIS
  Creates an Operational Analytics DW database for tenant query data

.DESCRIPTION
  Creates the operational tenant analytics DW database for result sets queries from Elastic jobs. Database is created in the resource group
  created when the WTP application was deployed.

#>
param(
    [Parameter(Mandatory=$true)]
    [string]$WtpResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$WtpUser
)

Import-Module $PSScriptRoot\..\..\Common\SubscriptionManagement -Force

# Get Azure credentials if not already logged on,  Use -Force to select a different subscription 
Initialize-Subscription

Import-Module $PSScriptRoot\..\..\WtpConfig -Force

$config = Get-Configuration

$catalogServerName = $($config.CatalogServerNameStem) + $WtpUser
$databaseName = $config.TenantAnalyticsDWDatabaseName

# Check if Analytics DW database has already been created 
$TenantAnalyticsDWDatabaseName = Get-AzureRmSqlDatabase `
                -ResourceGroupName $WtpResourceGroupName `
                -ServerName $catalogServerName `
                -DatabaseName $databaseName `
                -ErrorAction SilentlyContinue

if($TenantAnalyticsDWDatabaseName)
{
    Write-Output "Tenant Analytics DW database '$databaseName' already exists."
    exit
}

Write-output "Initializing the DW database '$databaseName'..."

# Create the tenant analytics DW database
New-AzureRmSqlDatabase `
    -ResourceGroupName $WtpResourceGroupName `
    -ServerName $catalogServerName `
    -DatabaseName $databaseName `
    -RequestedServiceObjectiveName "DW400" `
    > $null

# Creating tables in tenant analytics database
$commandText = "
-- Create table for storing raw tickets data. 
-- Tables for raw data contains an indentity column for tracking purposes.
IF (OBJECT_ID('raw_Tickets')) IS NOT NULL DROP TABLE raw_Tickets
CREATE TABLE [dbo].[raw_Tickets](
	[RawTicketId] int identity(1,1) NOT NULL,
	[VenueId] [int] NULL,
	[CustomerEmailId] [int] NULL,
	[TicketPurchaseId] [int] NULL,
	[PurchaseDate] [datetime] NULL,
	[PurchaseTotal] [money] NULL,
	[EventId] [int] NULL,
	[RowNumber] [int] NULL,
	[SeatNumber] [int] NULL
)
GO

-- Create table for storing raw customer data. 
IF (OBJECT_ID('raw_Customers')) IS NOT NULL DROP TABLE raw_Customers
CREATE TABLE [dbo].[raw_Customers](
	[RawCustomerId] int identity(1,1) NOT NULL,
	[VenueId] [int] NULL,
	[CustomerEmailId] [int] NULL,
	[CustomerPostalCode] [char](10) NULL,
	[CustomerCountryCode] [char](3) NULL
)
GO

--Create table for storing raw events data. 
IF (OBJECT_ID('raw_Events')) IS NOT NULL DROP TABLE raw_Events
CREATE TABLE [dbo].[raw_Events](
	[RawEventId] int identity(1,1) NOT NULL,
	[VenueId] [int] NULL,
	[EventId] [int] NULL,
	[EventName] [nvarchar](50) NULL,
	[EventSubtitle] [nvarchar](50) NULL,
	[EventDate] [datetime] NULL
)
GO

--Create table for storing raw venues data. 
IF (OBJECT_ID('raw_Venues')) IS NOT NULL DROP TABLE raw_Venues
CREATE TABLE [dbo].[raw_Venues](
	[RawVenueId] int identity(1,1) NOT NULL,
	[VenueId] [int] NULL,
	[VenueName] [nvarchar](50) NULL,
	[VenueType] [char](30) NULL,
	[VenuePostalCode] [char](10) NULL,
        [VenueCountryCode] [char](3) NULL,
	[VenueCapacity] [int] NULL
)
GO

--Create fact and dimension tables for the star-schema
-- Create a dimension table for events in tenantanalytics database.
-- Dimension table contains a surrogate key.
IF (OBJECT_ID('dim_Events')) IS NOT NULL DROP TABLE dim_Events
CREATE TABLE [dbo].[dim_Events] 
	([SK_EventId] int identity(1,1) NOT NULL,
        [VenueId] [int] NULL,
	[EventId] [int] NULL,
	[EventName] [nvarchar](50) NULL,
	[EventSubtitle] [nvarchar](50) NULL,
	[EventDate] [datetime] NULL
)
GO

-- Create a dimension table for venues in tenantanalytics database 
IF (OBJECT_ID('dim_Venues')) IS NOT NULL DROP TABLE dim_Venues
CREATE TABLE [dbo].[dim_Venues] 
	([SK_VenueId] int identity(1,1) NOT NULL,
        [VenueId] [int] NOT NULL,
	[VenueName] [nvarchar](50) NOT NULL,
	[VenueType] [char](30) NOT NULL,
	[VenueCapacity] [int] NOT NULL,
	[VenuepostalCode] [char](10) NULL,
	[VenueCountryCode] [char](3) NOT NULL
)
GO

-- Create a dimension table for customers in tenantanalytics database 
IF (OBJECT_ID('dim_Customers')) IS NOT NULL DROP TABLE dim_Customers
CREATE TABLE [dbo].[dim_Customers] 
	([SK_CustomerId] int identity(1,1) NOT NULL,
        [CustomerEmailId] [int] NULL,
	[CustomerPostalCode] [char](10) NULL,
	[CustomerCountryCode] [char](3) NULL
)
GO

--Create a dimension table for dates
IF (OBJECT_ID('dim_Dates')) IS NOT NULL DROP TABLE dim_Dates
CREATE TABLE [dbo].[dim_Dates](
        [SK_DateId] int identity(1,1) NOT NULL,
	[PurchaseDateID] [int] NULL,
	[DateValue] [date] NULL,
	[DateYear] [int] NULL,
	[DateMonth] [int] NULL,
	[DateDay] [int] NULL,
	[DateDayOfYear] [int] NULL,
	[DateWeekday] [int] NULL,
	[DateWeek] [int] NULL,
	[DateQuarter] [int] NULL,
	[DateMonthName] [nvarchar](30) NULL,
	[DateQuarterName] [nvarchar](31) NULL,
	[DateWeekdayName] [nvarchar](30) NULL,
	[MonthYear] [nvarchar](34) NULL
)
GO

--Prepopulate Date Dimension table
IF (OBJECT_ID('dim_dates')) IS NOT NULL DROP TABLE dim_dates;
WITH BaseData AS (SELECT A=0 UNION ALL SELECT A=1 UNION ALL SELECT A=2 UNION ALL SELECT A=3 UNION ALL SELECT A=4 UNION ALL SELECT A=5 UNION ALL SELECT A=6 UNION ALL SELECT A=7 UNION ALL SELECT A=8 UNION ALL SELECT A=9)
,DateSeed AS (SELECT RID = ROW_NUMBER() OVER (ORDER BY A.A) FROM BaseData A CROSS APPLY BaseData B CROSS APPLY BaseData C CROSS APPLY BaseData D CROSS APPLY BaseData E)
,DateBase AS (SELECT TOP 18628 DateValue = cast(DATEADD(D, RID,'1979-12-31')AS DATE) FROM DateSeed)

SELECT DateID = cast(replace(cast(DateValue as varchar(25)),'-','')as int)
        ,DateValue = cast(DateValue as date)
	,DateYear = DATEPART(year, DateValue)  
	,DateMonth = DATEPART(month, DateValue)  
	,DateDay = DATEPART(day, DateValue)  
	,DateDayOfYear = DATEPART(dayofyear, DateValue)  
	,DateWeekday = DATEPART(weekday, DateValue)
	,DateWeek = DATEPART(week, DateValue)
	,DateQuarter = DATEPART(quarter, DateValue)						
	,DateMonthName = DATENAME(month, DateValue)						
	,DateQuarterName = 'Q'+DATENAME(quarter, DateValue)						
	,DateWeekdayName = DATENAME(weekday, DateValue)
	,MonthYear = LEFT(DATENAME(month, DateValue),3)+'-'+DATENAME(year, DateValue)  
INTO dim_Dates
FROM DateBase

-- Create a fact table for tickets in tenantanalytics database 
IF (OBJECT_ID('fact_Tickets')) IS NOT NULL DROP TABLE fact_Tickets
CREATE TABLE [dbo].[fact_Tickets] 
	([TicketPurchaseId] [int] NOT NULL,
	[EventId] [int] NOT NULL,
	[CustomerEmailId] [int] NOT NULL,
	[VenueID] [int] NOT NULL,
	[PurchaseDateID ] [int] NOT NULL,
	[PurchaseTotal] [money] NOT NULL,
	[DaysToGo] [int] NOT NULL,
	[RowNumber] [int] NOT NULL,
	[SeatNumber] [int] NOT NULL)
GO

-- Create a stored procedure in tenantanalytics-dw that populates the star-scehma tables 
IF (OBJECT_ID('sp_TransformRawData')) IS NOT NULL DROP PROCEDURE sp_TransformRawData
GO

CREATE PROCEDURE sp_TransformRawData 
AS
BEGIN

-- Get the maximum value from the tracking column and then transform rows < max value.
DECLARE @StagingVenueLastInsert int = (SELECT MAX(RawVenueId) FROM  [dbo].[raw_Venues]);

-- Upsert pattern: Create a table temporarily and insert existing rows that were not changed and 
-- modified rows explicitly inserting the identity column values from the dimension table.
-- As a best practice, avoid using Update statement for SQL Data Warehouse loading. Instead, use a 
-- of temporary table and insert statements.Next, insert into the table all the new rows automatically 
-- generating the surrogate key defined by identity. Next, archive the current dimension table and rename 
-- the temporary table to be the new dimension table. As a best practice, save the archived table till 
-- the next incremental run. 

-----------------------------------------------------------------
----------------Venue DIMENSION----------------------------------
-----------------------------------------------------------------
-- Create a temporary table to hold the existing non-modified rows 
-- in the dimension table, the modified rows and the new rows.
CREATE TABLE dim_Venue_temp 
        ([SK_VenueId] int identity(1,1) NOT NULL,
        [VenueId] [int] NULL,
	[VenueName] [nvarchar](50) NULL,
	[VenueType] [char](30) NULL,
	[VenueCapacity] [int] NULL,
	[VenuepostalCode] [char](10) NULL,
	[VenueCountryCode] [char](3) NULL
)

-- Allow values to be inserted explicitly in the identity column
-- to ensure that all existing rows get the same identity value
SET IDENTITY_INSERT dim_Venue_temp ON;

--Insert existing and modified rows in the temporary table.
INSERT INTO dim_Venue_temp (SK_VenueId , VenueId, VenueName, VenueType, VenueCapacity, VenuepostalCode, VenueCountryCode)
-- Existing rows in the dimension table that are not modified
SELECT c2.SK_VenueId,
       c2.VenueId,
       c2.VenueName,
       c2.VenueType,
       c2.VenueCapacity,
       c2.VenuepostalCode,
       c2.VenueCountryCode
FROM [dbo].[dim_Venues] AS c2
WHERE c2.VenueId NOT IN
(   SELECT  t2.VenueId
    FROM     [dbo].[raw_Venues] t2
    WHERE   t2.RawVenueId <= @StagingVenueLastInsert
)
UNION ALL
-- ALl modified ones
SELECT DISTINCT c.SK_VenueId,     -- Surrogate key taken from the dimension table
       t.VenueId,
       t.VenueName, 
       t.VenueType,
       t.VenueCapacity,
       t.VenuepostalCode,
       t.VenueCountryCode
FROM [dbo].[dim_Venues] AS c
INNER JOIN [dbo].[raw_Venues] AS t ON  t.VenueId = c.VenueId
WHERE   t.RawVenueId <= @StagingVenueLastInsert

--Turn off indentity_insert to autmatically generate surrogate keys for the new rows
SET IDENTITY_INSERT dim_Venue_temp OFF;

-- Insert all the new rows in the staging table.
INSERT INTO dim_Venue_temp (VenueId, VenueName, VenueType, VenueCapacity, VenuepostalCode, VenueCountryCode)
SELECT DISTINCT t.VenueId,
                       t.VenueName, 
	                   t.VenueType,
                       t.VenueCapacity,
	                   t.VenuepostalCode,
	                   t.VenueCountryCode
FROM      [dbo].[raw_Venues] AS t
WHERE t.RawVenueId <= @StagingVenueLastInsert
AND VenueId NOT IN
	(SELECT   VenueId
	FROM      [dbo].[dim_Venues]
	) 

-- Delete the archived dimension table if it exists
IF OBJECT_ID('last_dim_Venues') IS NOT NULL DROP TABLE last_dim_Venues; 

--Rename the current dimension table to be the archive table
--and the temporary table to be the new dimension table.
RENAME OBJECT dim_Venues TO last_dim_Venues
RENAME OBJECT dim_Venue_temp TO dim_Venues

-----------------------------------------------------------------
----------------Event DIMENSION----------------------------------
-----------------------------------------------------------------
DECLARE @StagingEventLastInsert int = (SELECT MAX(RawEventId) FROM  [dbo].[raw_Events])

-- Create a temporary table to hold the existing non-modified rows 
-- in the dimension table, the modified rows and the new rows.
CREATE TABLE dim_Event_temp 
        ([SK_EventId] int identity(1,1) NOT NULL,
        [VenueId] [int] NULL,
	[EventId] [int] NULL,
	[EventName] [nvarchar](50) NULL,
	[EventSubtitle] [nvarchar](50) NULL,
	[EventDate] [datetime] NULL
)

-- Allow values to be inserted explicitly in the inentity column
-- to ensure that all existing rows get the same identity value
SET IDENTITY_INSERT dim_Event_temp ON;

--Insert existing and modified rows in the temporary table.
INSERT INTO dim_Event_temp (SK_EventId , VenueId, EventId, EventName, EventSubtitle, EventDate)
--DECLARE @StagingEventLastInsert int = (SELECT MAX(RawEventId) FROM  [dbo].[raw_Events])
-- Existing rows in the dimension table that are not modified
SELECT c.[SK_EventId],
       c.[VenueId],
       c.[EventId],
       c.[EventName],
       c.[EventSubtitle],
       c.[EventDate]
FROM [dbo].[dim_Events] AS c
WHERE CONCAT(c.VenueId, c.EventId) NOT IN 
(   SELECT  CONCAT(t.VenueId, t.EventId)
    FROM     [dbo].[raw_Events] t
    WHERE   t.RawEventId <= @StagingEventLastInsert
)

UNION ALL

-- All modified ones
SELECT DISTINCT c.[SK_EventId],
                t.[VenueId],
		t.[EventId],
		t.[EventName],
		t.[EventSubtitle],
		t.[EventDate]
FROM [dbo].[dim_Events] AS c
INNER JOIN [dbo].[raw_Events] AS t ON  t.VenueId = c.VenueId AND t.EventId = c.EventId
WHERE   t.RawEventId <= @StagingEventLastInsert

--Turn off indentity_insert to autmatically generate surrogate keys for the new rows
SET IDENTITY_INSERT dim_Event_temp OFF;

-- New rows in staging table 
INSERT INTO dim_Event_temp (VenueId, EventId, EventName, EventSubtitle, EventDate)
SELECT DISTINCT t.[VenueId],
                t.[EventId],
		t.[EventName],
		t.[EventSubtitle],
		t.[EventDate]
FROM [dbo].[raw_Events] AS t
WHERE t.RawEventId <= @StagingEventLastInsert
AND CONCAT(VenueId, EventId) NOT IN
	(SELECT   Concat(VenueId, EventId)
	FROM      [dbo].[dim_Events]
	) 

-- Delete the archived dimension table if it exists
IF OBJECT_ID('last_dim_Events') IS NOT NULL DROP TABLE last_dim_Events; 

--Rename the current dimension table to be the archive table
--and the temporary table to be the new dimension table.
RENAME OBJECT dim_Events TO last_dim_Events
RENAME OBJECT dim_Event_temp TO dim_Events

-----------------------------------------------------------------
----------------CUSTOMER DIMENSION-------------------------------
-----------------------------------------------------------------
DECLARE @StagingCustomerLastInsert int = (SELECT MAX(RawCustomerId) FROM  [dbo].[raw_Customers]);

-- Create a temporary table to hold the existing non-modified rows 
-- in the dimension table, the modified rows and the new rows.
CREATE TABLE dim_Customer_temp 
        ([SK_CustomerId] int identity(1,1) NOT NULL,
	[VenueId] int NOT NULL,
        [CustomerEmailId] [int] NULL,
	[CustomerPostalCode] [char](10) NULL,
	[CustomerCountryCode] [char](3) NULL
)

-- Allow values to be inserted explicitly in the inentity column
-- to ensure that all existing rows get the same identity value
SET IDENTITY_INSERT dim_Customer_temp ON;

--Insert existing and modified rows in the temporary table.
INSERT INTO dim_Customer_temp (SK_CustomerId , VenueId, CustomerEmailId, CustomerPostalCode, CustomerCountryCode)
-- Existing rows in the dimension table that are not modified
SELECT c.SK_CustomerId,
       c.VenueId,
       c.CustomerEmailId,
       c.CustomerPostalCode,
       c.CustomerCountryCode
FROM [dbo].[dim_Customers] AS c
WHERE CONCAT(c.VenueId, c.CustomerEmailId) NOT IN
(   SELECT  CONCAT(t.VenueId, t.CustomerEmailId)
    FROM     [dbo].[raw_Customers] t
    WHERE   t.RawCustomerId <= @StagingCustomerLastInsert
)
UNION ALL
-- All modified ones
SELECT DISTINCT c.SK_CustomerId,     -- Surrogate key taken from the dimension table
       t.VenueId,
       t.CustomerEmailId,
       t.CustomerPostalCode, 
	   t.CustomerCountryCode
FROM [dbo].[dim_Customers] AS c
INNER JOIN [dbo].[raw_Customers] AS t ON  t.CustomerEmailId = c.CustomerEmailId AND t.VenueId = c.VenueId
WHERE   t.RawCustomerId <= @StagingCustomerLastInsert

--Turn off indentity_insert to autmatically generate surrogate keys for the new rows
SET IDENTITY_INSERT dim_Customer_temp OFF;

-- New rows in staging table 
INSERT INTO dim_Customer_temp (VenueId, CustomerEmailId, CustomerPostalCode, CustomerCountryCode)
SELECT DISTINCT t.VenueId,
                t.CustomerEmailId,
                t.CustomerPostalCode, 
	            t.CustomerCountryCode
FROM      [dbo].[raw_Customers] AS t
WHERE t.RawCustomerId <= @StagingCustomerLastInsert
AND CONCAT(VenueId, CustomerEmailId) NOT IN
	(SELECT   CONCAT(VenueId, CustomerEmailId)
	FROM      [dbo].[dim_Customers]
	) 

-- Delete the archived dimension table if it exists
IF OBJECT_ID('last_dim_Customers') IS NOT NULL DROP TABLE last_dim_Customers;

--Rename the current dimension table to be the archive table
--and the temporary table to be the new dimension table.
RENAME OBJECT dim_Customers TO last_dim_Customers
RENAME OBJECT dim_Customer_temp TO dim_Customers

-----------------------------------------------------------------
----------------TICKETS FACTS------------------------------------
-----------------------------------------------------------------
DECLARE @StagingTicketLastInsert int = (SELECT MAX(RawTicketId) FROM  [dbo].[raw_Tickets]);

-- Merge tickets from raw data to the fact table
CREATE TABLE [dbo].[stage_fact_Tickets]
WITH (DISTRIBUTION = HASH(SK_VenueID),
  CLUSTERED COLUMNSTORE INDEX)
AS
-- Get new rows
SELECT DISTINCT t.TicketPurchaseId, 
                e.SK_EventId,
		c.SK_CustomerId,
		v.SK_VenueId,
		d.SK_DateId,
		t.PurchaseTotal,
		SaleDay = 60 - DATEDIFF(d, CAST(t.PurchaseDate AS DATE), CAST(e.EventDate AS DATE)),
		t.RowNumber,
		t.SeatNumber
FROM [dbo].[raw_Tickets] AS t
INNER JOIN [dbo].[dim_Events] e on t.EventId = e.EventId AND t.VenueId = e.VenueId
INNER JOIN [dbo].[dim_Venues] v on t.VenueID = v.VenueId
INNER JOIN [dbo].[dim_Customers] c on t.CustomerEmailId = c.CustomerEmailId AND t.VenueId = c.VenueId
INNER JOIN [dbo].[dim_Dates] d on CAST(t.PurchaseDate AS DATE) = d.DateValue
WHERE RawTicketId <= @StagingTicketLastInsert
UNION ALL  
-- Union all with unmodified rows
SELECT ft.TicketPurchaseId, ft.SK_EventId, ft.SK_CustomerId, ft.SK_VenueID, ft.SK_DateId, ft.PurchaseTotal, ft.DaysToGo, ft.RowNumber, ft.SeatNumber
FROM      [dbo].[fact_Tickets] AS ft
WHERE CONCAT(TicketPurchaseId, SK_VenueId, SK_EventId) NOT IN
(   SELECT   CONCAT(TicketPurchaseId, VenueId, EventId)
    FROM [dbo].[raw_Tickets] t
	--INNER JOIN [dbo].[raw_Events] ve on t.VenueId = ve.VenueId AND t.EventId = ve.EventId 
	WHERE RawTicketId <= @StagingTicketLastInsert 
);

-- If the archived fact table exists delete it.
IF OBJECT_ID('[dbo].[last_fact_Tickets]') IS NOT NULL  
DROP TABLE [dbo].[last_fact_Tickets];

-- Rename the current fact table to the last fact table and rename the staging table to be the current fact table.
RENAME OBJECT [dbo].[fact_Tickets] TO last_fact_Tickets;
RENAME OBJECT dbo.[stage_fact_Tickets] TO [fact_Tickets];

END
;

-- When all testing is done, uncomment the following delete statements
-- Delete the rows in the staging table that are already transformed
-- DELETE FROM raw_Tickets
-- WHERE RawTicketId <= @StagingTicketLastInsert 

-- DELETE FROM [dbo].[raw_Events]
-- WHERE RawVenueEventId <= @StagingEventLastInsert 

-- DELETE FROM [dbo].[raw_Venues]
-- WHERE RawVenueEventId <= @StagingVenueLastInsert 

-- DELETE FROM [dbo].[raw_Customers]
-- WHERE RawVenueEventId <= @StagingCustomerLastInsert 
GO
"

$catalogServerName = $config.catalogServerNameStem + $WtpUser
$fullyQualifiedCatalogServerName = $catalogServerName + ".database.windows.net"

Write-output "Populating the DW database with predefined tables and stored pocedure..."

Invoke-SqlcmdWithRetry `
-ServerInstance $fullyQualifiedCatalogServerName `
-Username $config.CatalogAdminUserName `
-Password $config.CatalogAdminPassword `
-Database $databaseName `
-Query $commandText `
-ConnectionTimeout 30 `
-QueryTimeout 30 `
> $null  

$tenantsServerName = $($config.TenantServerNameStem) + $WtpUser 
$fullyQualifiedTenantServerName = $tenantsServerName + ".database.windows.net"

$databaseName = $config.TenantAnalyticsDWDatabaseName
$storagelocation = $config.TableNamesStorageLocation
$containerName = $config.TableNamesContainerName

# Creating a storage account for data staging and for saving any additional configuration files required by Azure Data Factory
Write-Output "Creating storage account..."

# Create a storage account and upload the configuration file in it.
try {
    $storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $WtpResourceGroupName -Name $config.storageAccountADF
}
catch {
    $storageAccount = New-AzureRmStorageAccount -ResourceGroupName $WtpResourceGroupName `
        -Name $config.storageAccountADF `
        -Location $storagelocation `
        -SkuName Standard_LRS `
        -Kind Storage
        
    $ctx = $storageAccount.Context

    Write-Output "Creating a container in the storage account..."
    
    # Create a container in the blob storage
    New-AzureStorageContainer -Name $containerName -Context $ctx -Permission blob

    Write-Output "Uploading Table configuration file in the container..."

    # Upload table config file containing names and structures of source and destination tables, columns names for the source table, 
    # source tracker column name and mapping between the source and destination table.
    Set-AzureStorageBlobContent -File "$PSScriptRoot\TableConfig.json" `
        -Container $containerName `
        -Blob "TableConfig.json" `
        -Context $ctx 

}

# Get the account key for the storage account.
$storagekey = (Get-AzureRmStorageAccountKey -ResourceGroupName $WtpResourceGroupName -AccountName $storageAccount.StorageAccountName).Value[0]

# Creating connection strings SQL Database, Data Warehouse and Blob Storage.
$dbconnection = "Server=tcp:" + $fullyQualifiedTenantServerName + ",1433;Database=@{linkedService().DBName};User ID=" + $config.TenantAdminUserName + "@" + $tenantsServerName + ";Password=" + $config.TenantAdminPassword + ";Trusted_Connection=False;Encrypt=True;Connection Timeout=90"
$dwconnection = "Server=tcp:" + $fullyQualifiedCatalogServerName + ",1433;Database=@{linkedService().DBName};User ID=" + $config.CatalogAdminUserName + "@" + $catalogServerName + ";Password=" + $config.TenantAdminPassword + ";Trusted_Connection=False;Encrypt=True;Connection Timeout=90"
$storageconnection = "DefaultEndpointsProtocol=https;AccountName=" + $storageAccount.StorageAccountName + ";AccountKey=" + $storagekey

# Converting to secure string
$secureStringdbconnection = ConvertTo-SecureString $dbconnection -AsPlainText -Force
$secureStringdwconnection = ConvertTo-SecureString $dwconnection -AsPlainText -Force
$secureStringstorageconnection = ConvertTo-SecureString $storageconnection -AsPlainText -Force


#$secureStringdbconnection =  $dbconnection 
#$secureStringdwconnection =  $dwconnection 
#$secureStringstorageconnection =  $storageconnection

Write-Output "Deploying Azure Data Factory..."

# Deploy a data factory in the resource group. If the data factory already exists, a message will appear asking if you want to replace it.
$DataFactory = Set-AzureRmDataFactoryV2 -ResourceGroupName $WtpResourceGroupName -Location $config.DataFactoryLocation -Name $config.DataFactoryName

Write-Output "Deploying the data factory objects..."

# Deploying arm template containing Azure Data Factory objects such as pipelines, linked services, and datasets.
try {
    # Use an ARM template to create all data factory objects required for copying data in this sample
    $deployment = New-AzureRmResourceGroupDeployment `
            -TemplateFile ($PSScriptRoot + "\" + $config.DataFactoryDeploymentTemplate) `
            -ResourceGroupName $WtpResourceGroupName `
            -factoryName $config.DataFactoryName `
            -AzureSqlDatabase_connectionString $secureStringdbconnection `
            -AzureSqlDataWarehouse_connectionString $secureStringdwconnection `
            -AzureStorage_connectionString $secureStringstorageconnection `
            -ErrorAction Stop `
            -Verbose
}
catch {
        Write-Error $_.Exception.Message
        Write-Error "An error occured deploying the Azure Data Factory objects "
        throw
}

