## Plymouth Theme
Original : https://www.gnome-look.org/p/1111249

### Where ?
Copy the `ubuntu-spinner-logo` dir to `/usr/share/plymouth/themes`, then run :  
```bash
sudo update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth /usr/share/plymouth/themes/ubuntu-spinner-logo/ubuntu-spinner-logo.plymouth 100
sudo update-alternatives --config default.plymouth
sudo update-initramfs -u
```

### And for the spinner ?
Go to `svg_to_png_animation`, put your animated svg in the folder, edit the required things in `convert.js` (fps, duration, svgFilePath)  
Maybe you will need to run `export CHROME_DEVEL_SANDBOX=/opt/google/chrome/chrome-sandbox` (tweak to your path)  
Then `npm i --no-audit --no-funding` and `npm run convert`  
You can `npm run mp4` and `npm run gif` if you want (just to check if it loops correctly), although the video will look awful and the gif will either have 1 or 0 transparency (so no semi-transparent glow for instance). Delete the generated files before re-running them  
Finally, do `sudo cp -r frames /usr/share/plymouth/themes/ubuntu-spinner-logo/spinner`

