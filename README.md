# plping   & plmtr     for batch processing IPs from file...
---
***UPDATE*** 2020-07-02  
0. This is a Bash script
1. Script can be use on Linux & MacOS X
2. You can add note after each IP in the ipfile
---
Usage:  
**`plping.sh [filename] [count]  `**   
**`plping.sh [filename]   `** (default count = 10)  
  
**`plmtr.sh [filename] [count]  `**     
**`plmtr.sh [filename]   `** (default count = 10)   

**`chmod +x plping.sh`**<br>
**`chmod +x plmtr.sh`** 

eg：  
**`./plping.sh ipfile 15`**  
**`sudo ./plmtr.sh ipfile 100`**

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
`plping ipfile 15`

Prompt display
```ubuntu
1 of 5 Loss:0% Avg:0.636 Finished: 192.168.123.1 local
2 of 5 Loss:0% Avg:42.499 Finished: 114.114.114.114 DNS-CN
3 of 5 Loss:100% Avg: Finished: www.google.com Website
4 of 5 Loss:0% Avg:9.629 Finished: www.baidu.com CN
5 of 5 Loss:0% Avg:23.368 Finished: 1.1.1.1 

Finish Time: 2020年 06月 25日 星期四 22:57:07 CST
Output File: ipfile.log   Detail File: ipfile.logb
Duration of this script: 1m22s    Count: 15
```

There will be 2 output files creat in the same path of input file .  
**.log**  as the prompt display  
**.logb** as the detail of the ping
