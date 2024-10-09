$user = $env:UserName
$Server1 = $env:logonserver
$computer=(Get-WmiObject -Class Win32_ComputerSystem -Property Name).Name
$date1 = get-Date
$date2 = $date1.ToShortDateString()
$time1 = $date1.ToShortTimeString()
$ipV4 = Test-Connection -ComputerName (hostname) -Count 1  | Select -ExpandProperty IPV4Address

'Logoff - User: ' + $user + ", " + "Computer: " + $computer + ", " + $ipV4.IPAddressToString + ", Logon Server: " + $Server1 + ", " + $date2 + ", " + $time1 | out-file -filepath "\\192.168.1.203\111\$ipV4.txt" -append -width 200

