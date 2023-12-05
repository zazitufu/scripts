# plping   & plmtr     for batch processing IPs from file...
---
***UPDATE*** 2023-12-05  

1. Script can be use on Linux & MacOS X
2. You can add note after each IP in the ipfile
3. This is a Bash script
---
Usage:  
**`plping.sh [filename] [-c count] [-t tag] `**   
**`plping.sh [filename]   `** (default count = 10)  
  
**`plmtr.sh [filename] [-c count] [-t tag]  `**     
**`plmtr.sh [filename]   `** (default count = 10)   

**`chmod +x plping.sh`**<br>
**`chmod +x plmtr.sh`** 

eg：  
**`./plping.sh ipfile -c 15`**  
**`./plping.sh ip* -c 15`**  
**`sudo ./plmtr.sh ipfile -c 100 -t tag1`**

The iplist file should be one IP/DOMAIN each line  
```
cat ipfile  

192.168.123.1 local
114.114.114.114 DNS-CN
www.google.com Website
www.baidu.com CN
1.1.1.1 
```
---
eg:
`plping ipfile -c 15`

Prompt display
```ubuntu
Total-IPs: 5 [=================================================>][100.00%]
 1 of 5  Loss:100.00% Avg:~~~ms      Mdev:~ms        local              : 192.168.123.1   
 2 of 5  Loss:0.00%   Avg:32.743ms   Mdev:0.741ms    DNS-CN             : 114.114.114.114 
 3 of 5  Loss:100.00% Avg:~~~ms      Mdev:~ms        Website            : www.google.com  
 4 of 5  Loss:0.00%   Avg:9.872ms    Mdev:0.426ms    CN                 : www.baidu.com   
 5 of 5  Loss:0.00%   Avg:149.729ms  Mdev:0.676ms    ~~~~~~             : 1.1.1.1         

Finish Time: Tue Dec  5 17:06:55 CST 2023
Output File: i2.log   Detail File: i2.logb
Duration of this script: 19s    Count: 15

```

There will be 2 output files creat in the same path of input file .  
**.log**  as the prompt display  
**.logb** as the detail of the ping
