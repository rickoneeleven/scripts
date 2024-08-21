$user = $env:UserName
$Server1 = $env:logonserver
$computer=(Get-WmiObject -Class Win32_ComputerSystem -Property Name).Name
$date1 = get-Date
$date2 = $date1.ToShortDateString()
$time1 = $date1.ToShortTimeString()
$ipV4 = Test-Connection -ComputerName (hostname) -Count 1  | Select -ExpandProperty IPV4Address

'Logoff' + "," + $user + "," + "'" + $computer + "," + $ipV4.IPAddressToString + "," + $Server1 + "," + $date2 + "," + $time1 | out-file -filepath \\PATH TO SHAREPOINT\$user.csv -append -width 200
'Logoff' + "," + $user + "," + "'" + $computer + "," + $ipV4.IPAddressToString + "," + $Server1 + "," + $date2 + "," + $time1 | out-file -filepath \\PATH TO SHAREPOINT\$computer.csv -append -width 200

