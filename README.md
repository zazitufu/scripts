# plping   & plmtr  
Usage:  
`plping [filename] [count]  `
  
eg：  
`plping ip.txt 10  `
  
Output file will be in current fold as filename.log  
eg:  
`ip.txt.log  `
  
The input file should be one IP/DOMAIN each line  
```
cat ip.txt  

192.168.123.1
114.114.114.114
www.google.com
www.baidu.com
1.1.1.1  
```

Output file
```
#tail ip2.log

--- 1.1.1.1 ping statistics ---
10 packets transmitted, 10 received, 0% packet loss, time 9018ms
rtt min/avg/max/mdev = 18.668/19.485/20.691/0.678 ms


Finish Time: 2020年 06月 14日 星期日 01:47:51 CST
This shell script execution duration: 57s

```

Prompt display
```
1 of 5 Finished: 192.168.123.1
2 of 5 Finished: 114.114.114.114
3 of 5 Finished: www.google.com
4 of 5 Finished: www.baidu.com
5 of 5 Finished: 1.1.1.1

Output File: ip2.log
This shell script execution duration:  57s

```
