#!/bin/bash
## 修复主题agnoster的prompt设置，避免在使用自动补全指令的插件的时候，快速按tab键会造成首字母残留，并且无法被backspace删除的问题。
# 主题文件路径
THEME_FILE="$HOME/.oh-my-zsh/themes/agnoster.zsh-theme"

# 检查主题文件是否存在
if [ ! -f "$THEME_FILE" ]; then
    echo "agnoster.zsh-theme not found at $THEME_FILE"
    exit 1
fi

# 备份原始主题文件
cp "$THEME_FILE" "${THEME_FILE}.bak"

# 注释掉原有的 PROMPT 行，并添加新的 PROMPT 行
sed -i '/^PROMPT=/ s/^/#/' "$THEME_FILE"
echo "PROMPT='%{%f%b%k%}\$(build_prompt)%{ %}'" >> "$THEME_FILE"

# 提示完成
echo "agnoster theme modified successfully."
