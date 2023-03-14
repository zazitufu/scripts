###用来批量修改v2rayN导出的内容里的id
### bash chuuid.sh "newID"
### 产生3个文件，b1是解码完的，b2是解码完并且修改完ID的，b3是将修改完id的重新base64编码。
### 2023年3月14日
#!/bin/bash
#删除上次残留文件
rm b1 b2 b3
# read each line from input file
while read line; do
  # remove "vmess://" from beginning of line
  line="${line#vmess://}"

  # decode base64
  decoded_line=$(echo "$line" | base64 -d)

  # modify ID
  modified_line=$(echo "$decoded_line" | jq --arg id "$1" '.id=$id' | tr -d '\n')

  # encode with "vmess://" at beginning of line
  encoded_line="vmess://$(echo "$modified_line" | base64 -w 0)"

  # output to appropriate file
  echo "$decoded_line" >> b1
  echo "$modified_line" >> b2
  echo "$encoded_line" >> b3
done < aaa
