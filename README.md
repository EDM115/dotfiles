# `EDM115/dotfiles`
My config files  
Also containing some scripts and lists of packages, used to setup back my environment  
More info on [REINSTALL.md](./REINSTALL.md)

---

## Linux :penguin:

Files :
- [.zshrc](.zshrc) : Zsh configuration file. Includes : Oh My Zsh, Oh My Posh, fzf, zoxide and more
- [apt-fast.conf](apt-fast.conf) : Apt-fast configuration file
- [apt.txt](apt.txt) : List of apt packages. May contain extra libs (`apt list --installed | grep -F '[installé]' | cut -d '/' -f 1 > apt.txt`)
- [cargo.linux.txt](cargo.linux.txt) : List of Rust packages (`cargo install --list > cargo.linux.txt`)
- [flatpak.txt](flatpak.txt) : List of flatpak packages (`flatpak list --columns=name,application > flatpak.txt`)
- [grub](./grub) : My grub config (from `/etc/default/grub`)
- [homebrew.txt](homebrew.txt) : List of Homebrew packages (`brew list > homebrew.txt`)
- [launch-discord.sh](launch-discord.sh) & [upgrade-discord.sh](upgrade-discord.sh) : Scripts to launch and upgrade Discord ([source](https://gist.github.com/EDM115/5b6918c4433de7038588c78d602f7de5))

Folders :
- [apt/sources.list.d/](apt/sources.list.d/) : Sources list for apt
- [grub_theme/](grub_theme/) : Custom GRUB theme
- [plymouth_theme](plymouth_theme/) : Custom Plymouth theme, along with js thing to generate the images for the spinner. Currently broken (sorta)

---

## Windows :window:

Files :
- [cargo.win.txt](cargo.win.txt) : List of Rust packages (`cargo install --list > cargo.win.txt`)
- [dracula.psd1](dracula.psd1) : Dracula colorscheme for [Terminal-Icons](https://github.com/devblackops/Terminal-Icons)
- [ptr.toml](ptr.toml) : Installed PowerToys Run plugins, comes from `C:\Users\EDM115\AppData\Local\Microsoft\PowerToys\PowerToys Run\Plugins\version.toml`. Tool : [8LWXpg/ptr](https://github.com/8LWXpg/ptr)
- [windows-terminal.json](windows-terminal.json) : Config for the Windows Terminal
- [winget.txt](winget.txt) : Installed winget packages. Obtained through `Get-WinGetPackage | Format-Table -AutoSize | Out-File -Width 500 -FilePath winget.txt`

---

## Both :nerd_face:

Files :
- [.gitconfig](.gitconfig) : Git configuration file
- [gh-extensions.txt](gh-extensions.txt) : List of extensions for the GH CLI (`gh extension list > gh-extensions.txt`)
- [Microsoft.PowerShell_profile.ps1](Microsoft.PowerShell_profile.ps1) : PowerShell profile. Includes : Oh My Posh, Terminal-Icons, Github Copilot, hcloud, [sudo-like](https://gist.github.com/EDM115/daff204ae4bb19f0a90291d036e433ed) and more
- [pnpm.json](pnpm.json) : List of globally installed PNPM packages (`pnpm ls -g --json > pnpm.json`)
- [pip.txt](pip.txt) : List of installed Pip packages (`pip freeze > pip.txt`)
- [powershell.config.json](powershell.config.json) : PowerShell configuration file (in `Split-Path $PROFILE.CurrentUserCurrentHost` so far)
- [vscode-extensions.txt](vscode-extensions.txt) : List of VSCode extensions. Reinstall with [this script](https://gist.github.com/EDM115/7f90913892cf5dd0e5141316ea37b261)
- [vscode-settings.json](vscode-settings.json) : VSCode settings

Folders :
- [omp/](omp/) : Oh My Posh themes ([source](https://github.com/EDM115/EDM115-ohmyposh-theme))
- [spicetify/](spicetify/) : Spicetify config, themes and extensions, as well as a marketplace backup
