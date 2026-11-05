# Ratnam Store Billing — setup guide for a shop

Version 1.25.0. This guide is for the person who installs the program in a shop (you, or your engineer).
It takes about 30 minutes the first time.

## What is installed where

- **The main computer** of the shop (usually the billing computer, or the owner's computer that is on all day)
  gets SQL Server Express (the database) and the program. The program runs in the background as a Windows service:
  it starts with the computer, nobody needs to open it.
- **Other computers** of the shop (a second billing counter, the owner's laptop) need nothing installed. They open
  the program in Chrome or Edge, with the main computer's address, for example `http://192.168.1.10:5000`.
- The main computer must be on while anybody uses the program.

What the main computer needs: Windows 10 or 11 (64-bit), 8 GB memory, 10 GB free disk. Chrome or Edge.

## Step 1 — Install SQL Server Express (free, once)

1. Download "SQL Server 2022 Express" from Microsoft's site (search "SQL Server 2022 Express download").
2. Run it and choose **Basic**. Accept the licence, keep the folder it suggests, press Install.
3. When it says "Installation has completed successfully", note the instance name. It is normally `SQLEXPRESS`.
   Close the window. (You do not need SQL Server Management Studio.)

Install it **as the same Windows user** who will run the install script in step 2 (that user becomes the
database administrator).

## Step 2 — Install the program

1. Copy `RatnamStoreBilling-1.25.0.zip` to the main computer and unzip it (right-click → Extract All), for example
   to `C:\Setup\RatnamStoreBilling-1.25.0`.
2. Open the Start menu, type `PowerShell`, right-click **Windows PowerShell** → **Run as administrator**.
3. Type these two lines (change the folder and the shop name to yours):

   ```
   cd C:\Setup\RatnamStoreBilling-1.25.0
   powershell -ExecutionPolicy Bypass -File .\install.ps1 -ShopName "Shree Krishna Kirana Store" -VendorPhone "98250 12345"
   ```

   Other choices you can add to the line (all optional):

   | Add this | When |
   |---|---|
   | `-Port 5001` | Another program already uses port 5000 |
   | `-SqlInstance "."` | A full SQL Server (not Express) is used |
   | `-InstallDir "D:\RatnamStore"` | Install on another drive (the backups go there too) |
   | `-AdminPassword "Shop@2026"` | A different first password for the `admin` login |

4. Wait until it says **"Ratnam Store Billing 1.25.0 is installed."** (the first start makes the database; it can
   take a minute or two). It shows:
   - the address on this computer: `http://localhost:5000`
   - the address for the other computers, e.g. `http://192.168.1.10:5000`
   - the first login: `admin` / `Admin@123`

What the script did: a SQL login only for the program, the folders `C:\RatnamStore\app` (the program) and
`C:\RatnamStore\backup` (the backups), the settings file `C:\RatnamStore\app\appsettings.Production.json`
(the database password and a secret key, made at random), the Windows service **Ratnam Store Billing**, a firewall
opening for the other computers (private networks only), and two shortcuts on the desktop.

## Step 3 — First start in the shop

1. Double-click **Store Billing** on the desktop. Log in with `admin` / `Admin@123`.
2. **Change the password at once**: top right (the person icon) → Change password.
3. The start screen asks for the shop's details (name, address, GST or no GST, the bill printer). Fill it in.
4. Products: add them one by one (Products → Add product), from Excel (Products → Excel → Import from Excel),
   or, to try the program first, press **Add sample products** on the empty Products page (32 kirana products;
   take them away later with Products → Excel → Import from Excel → "Sample products" → Undo).
5. Cashiers: Settings → Cashiers → Add cashier (each cashier has their own login).

## Step 4 — The other computers of the shop

On each other computer, open Chrome or Edge and type the address the install showed, for example
`http://192.168.1.10:5000`. Make a desktop shortcut or bookmark.

If it does not open:
- Both computers must be on the same network (the same Wi-Fi router or switch).
- On the main computer the network must be **Private**: Settings → Network & Internet → (your network) →
  Network profile → Private. The firewall opening is only for private networks.
- The main computer's address can change when the router restarts. Ask the person who looks after the router to
  give the main computer a fixed address (DHCP reservation), or use the computer's name instead:
  `http://BILLING-PC:5000` (Settings → About this program shows the name and the addresses).

## Step 5 — The bill printer

- Choose the bill printer as the **default printer** in Windows (Settings → Bluetooth & devices → Printers), and
  set its paper (80 mm / 58 mm) in the printer's own settings.
- In the program: Settings → Shop, GST and bill → Bill printer, and per counter in Settings → Billing counters.
- **Print without the print window**: use the desktop shortcut **Store Billing (quick print)** (made when Chrome is
  installed). It opens the program in Chrome with "kiosk printing", so the bill prints at once on the default
  printer.

## Step 6 — The licence

A new shop gets a **free trial of 30 days** with every option. After the trial (or after a licence ends), the
program is **read-only**: everything can still be seen and printed, and backups work, but new bills and entries
cannot be saved until a licence key is entered. Nothing is ever deleted.

To get the key:
1. Settings → Licence → **Copy licence request** (or **Send request** on WhatsApp). The request has the shop's
   **Company ID**, which the key must be made for.
2. Send it to the software supplier. They make the key in License Studio and send it back.
3. Settings → Licence → paste the key → **Enter key**. A key is one long line with one dot in it; copy all of it.

What the licence shows: until when it works, how many users may be active, and which options are in the plan.
An option not in the plan shows "not in your licence" in Settings. 15 days before the end a yellow line reminds
the owner; after the end date the program still works 7 more days (red line), then it is read-only until the
renewed key is entered.

## Step 7 — Backups (important)

- The program makes an **automatic backup every day at 21:00** in `C:\RatnamStore\backup` and keeps the last 15.
  If the computer was off at 21:00, it makes the backup as soon as the computer is on again.
- Change it in Settings → Backup → Automatic backup every day. Also choose **"Also copy to this folder"**: a pen
  drive (e.g. `E:\ShopBackup`) or a Google Drive / OneDrive folder on this computer, so a copy is away from the
  computer's own disk. A backup on the same disk does not help when the disk breaks.
- Settings → Backup → **Download** saves a backup on the computer you are using.
- **Restore** puts the data back as it was in a backup (a backup of today's data is made first, so a restore can be
  taken back too). The licence key is not changed by a restore.

## Step 8 — Updating to a new version

1. Unzip the new package on the main computer.
2. PowerShell **as administrator**, in the new package's folder:

   ```
   powershell -ExecutionPolicy Bypass -File .\update.ps1
   ```

3. It makes a backup of the database first (`..._before-update_....bak`), stops the program, puts the new files
   in place (the settings file stays), and starts it again. The database is brought up to date by the program.
4. On every computer press **Ctrl+F5** once in the browser.

Ask the shop to stop billing for the 2 minutes the update takes.

## Moving to a new computer

1. Old computer: Settings → Backup → Back up now → Download (or take the newest file from `C:\RatnamStore\backup`).
2. New computer: steps 1 and 2 (same shop name).
3. Copy the backup file to the new computer; Settings → Backup → Restore from a file. Log in again with the old
   passwords. The licence key is the same (it is for the Company ID, not for the computer): enter it again if asked.

## Removing the program

PowerShell as administrator, in the package folder: `powershell -ExecutionPolicy Bypass -File .\uninstall.ps1`.
It removes the service, the firewall opening and the shortcuts. **The data stays** (the database and
`C:\RatnamStore\backup`). Add `-RemoveProgramFiles` to delete the program folder as well.

## Problems

| What you see | What to do |
|---|---|
| The install says SQL Server could not be reached | SQL Server Express is not installed, or has another name: add `-SqlInstance ".\NAME"`. In Windows "Services", **SQL Server (SQLEXPRESS)** must be Running. |
| "This Windows user is not an administrator of SQL Server" | Run the install as the Windows user who installed SQL Server. |
| The desktop shortcut shows "This site can't be reached" | In Windows "Services", start **Ratnam Store Billing**. If it stops again: Event Viewer → Windows Logs → Application, look for errors from **AccountingApi**. |
| The other computers cannot open it | See step 4 (Private network, the same network, the address). |
| "The backup did not work" | SQL Server must be allowed to write in `C:\RatnamStore\backup` (the install does this). If the folder was changed, give "NT SERVICE\MSSQL$SQLEXPRESS" Modify rights on it. |
| A red line "The free trial ended" / "The licence ended" | Enter the licence key: Settings → Licence. |
| "Your licence does not have …" | That option is not in the shop's plan. The supplier can make a key with a bigger plan. |
| The licence key is refused: "for company ID 2" | The key was made for another Company ID. Send the licence request again; the key must use this shop's Company ID. |
| Forgot the admin password | On the main computer, PowerShell as administrator: `cd C:\RatnamStore\app` then `.\AccountingApi.exe reset-password admin NewPass@123` (it says "New password set"). Log in with the new password and change it. |

Where things are: program `C:\RatnamStore\app`, settings `C:\RatnamStore\app\appsettings.Production.json`,
backups `C:\RatnamStore\backup`, database `StoreBilling` in SQL Server Express.
