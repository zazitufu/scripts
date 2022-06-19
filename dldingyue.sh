#!/bin/bash
## 从 dldingyue.txt 文件内的URL列表进行下载，每行第一列为下载链接，空格，第二列为下载后的自定义文件名
## 每次下载都覆盖本地旧文件

while read src_url des_file
do
    wget  "$src_url" -O $des_file
done < dldingyue.txt
