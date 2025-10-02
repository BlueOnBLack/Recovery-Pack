# Recovery Pack

**Recovery Pack** is a bootable recovery toolkit that integrates into your Windows Boot Menu using **WinRE** and **DART**. 

This project helps you recover systems, troubleshoot, and perform maintenance tasks.

### 1. Reconstruct Large Files (WinRAR)

Files in the `Sources` folder are **split due to GitHub limits**. To reconstruct:

1. Download the full `Sources` folder from GitHub.
2. Make sure all parts of a split archive (e.g., `install.part1.rar`, `install.part2.rar`, etc.) are in the same folder.
3. Right-click the first part (`install.part1.rar`) → **Extract Here** or **Extract to install**.
4. WinRAR will automatically merge all parts into the full file (e.g., `WinRe.wim`) in the folder.  

## Features

- Add **Recovery Pack** option to Windows boot menu
- Includes **WinRE + DART** environment
- Provides tools for recovery, diagnostics, and maintenance
