#!/bin/zsh
# Change theme in Oh-My-Zsh
## eg: agnoster.zsh-theme(theme filename)
## ./chomz agnoster
sed -i "/^ZSH_THEME=/cZSH_THEME=\"$1\"" ~/.zshrc
exec $SHELL -l
### Finish
