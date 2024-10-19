$LoginName="sqladmin"
$LoginPassword="Azure@345"
$DatabaseName="mssql_database"
$ServerName="vm.database.windows.net"
$DBQuery="CREATE DATABASE appdb"


Invoke-SqlCmd -ServerInstance $ServerName -U $LoginName -p $LoginPassword -Query $DBQuery


$LoginName="sqladmin"
$LoginPassword="Azure@345"
$ServerName="vm.database.windows.net"
$DatabaseName="mssql_database"
$ScriptFile="https://mf37commands.blob.core.windows.net/database-commands/01.sql"
$Destination="D:\01.sql"


Invoke-WebRequest -Uri $ScriptFile -OutFile $Destination
Invoke-SqlCmd -ServerInstance $ServerName -InputFile $Destination -Database $DatabaseName -Username $LoginName -Password $LoginPassword


