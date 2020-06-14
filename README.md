# plping   & plmtr     for batch processing IPs from file...

Usage:  
`plping.sh [filename] [count]  ` (default count = 10)  
`plmtr.sh [filename] [count]  ` (default count = 10)    

`chmod +x plping.sh`<br>
`chmod +x plmtr.sh` 

eg：  
`./plping.sh ip.txt 10`  
`./plmtr.sh ip.txt 100`

The iplist file should be one IP/DOMAIN each line  
```
cat ip.txt  

192.168.123.1
114.114.114.114
www.google.com
www.baidu.com
1.1.1.1  
```
---
Prompt display
```ubuntu
1 of 5 Loss:0% Avg:0.873 Finished: 192.168.123.1
2 of 5 Loss:0% Avg:32.259 Finished: 114.114.114.114
3 of 5 Loss:100% Avg: Finished: www.google.com
4 of 5 Loss:0% Avg:13.676 Finished: www.baidu.com
5 of 5 Loss:0% Avg:20.096 Finished: 1.1.1.1

Finish Time: 2020年 06月 14日 星期日 18:18:44 CST
Output File: **ip2.log**   Detail File: **ip2.logb**
This shell script execution duration:  58s
```

There will be 2 output files creat in the same path of input file .  
**.log**  as the prompt display  
**.logb** as the detail of the ping
