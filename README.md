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

192.168.123.123  
192.168.1.1  
www.google.com  
www.youtube.com  
1.1.1.1  
```

the output file
```
tail i2.log

--- 89.238.160.168 ping statistics ---
10 packets transmitted, 2 received, 80% packet loss, time 9142ms
rtt min/avg/max/mdev = 270.710/270.817/270.924/0.107 ms


Finish Time: 2020年 06月 14日 星期日 01:22:58 CST
This shell script execution duration: 1m23s
```

the prompt display
```
1 of 8 Finished: 45.144.242.4
2 of 8 Finished: 89.238.160.168
3 of 8 Finished: 38.65.25.167
4 of 8 Finished: 185.200.119.230
5 of 8 Finished: 185.183.104.240
6 of 8 Finished: 185.183.104.240
7 of 8 Finished: 81.90.189.197
8 of 8 Finished: 89.238.160.168

Output File: i2.log
This shell script execution duration:  1m23s
```
