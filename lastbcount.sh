#!/bin/bash
### 用来计算lastb里面各个ip有多少次失败的登录行为
### 2022年3月29日 15点34分
lastb | awk '{ print $3}' | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}"|sort | uniq -c | sort -nr | more
