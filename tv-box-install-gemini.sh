#!/bin/bash

# =================================================================
# Ubuntu PC -> TV Box Dönüştürücü (Couch Mode v2.0)
# Amaç: 3-4 metre uzaktan okunabilir, kumanda/mouse dostu arayüz.
# =================================================================

# -- 1. KULLANICI TESPİTİ (EN KRİTİK KISIM) --
# Script sudo ile çalışsa bile asıl kullanıcıyı bulmalıyız.
if [ "$EUID" -ne 0 ]; then
  echo "Lütfen bu scripti sudo ile çalıştırın: sudo $0"
  exit 1
fi

REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
USER_UID=$(id -u "$REAL_USER")

echo "İşlem yapılacak kullanıcı: $REAL_USER (UID: $USER_UID)"

# -- 2. FONKSİYON: KULLANICI ADINA KOMUT ÇALIŞTIRMA --
# Bu fonksiyon, root yetkisiyle değil, masaüstü oturumu sahibi adına ayar yapar.
run_as_user() {
    # DBUS adresini bul (Gsettings'in çalışması için şart)
    PID=$(pgrep -u "$USER_UID" gnome-session | head -n 1)
    if [ -z "$PID" ]; then
        PID=$(pgrep -u "$USER_UID" gnome-shell | head -n 1)
    fi
    
    export DBUS_SESSION_BUS_ADDRESS=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/"$PID"/environ | cut -d= -f2-)
    
    # Komutu kullanıcı olarak çalıştır
    su - "$REAL_USER" -c "export DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS; $1"
}

# -- 3. UYGULAMA KURULUMLARI --
install_apps() {
    echo "--- Gerekli Uygulamalar Kontrol Ediliyor ---"
    apt update
    
    # Kodi (Medya Merkezi)
    if ! command -v kodi &> /dev/null; then
        echo "Kodi kuruluyor..."
        apt install -y kodi
    fi

    # VLC (Video Oynatıcı)
    if ! command -v vlc &> /dev/null; then
        echo "VLC kuruluyor..."
        apt install -y vlc
    fi
    
    # GNOME Tweak Tool (İnce ayar için)
    apt install -y gnome-tweaks
}

# -- 4. TV ARAYÜZÜNE GEÇİŞ --
enable_tv_mode() {
    echo "--- TV Modu Aktif Ediliyor ---"

    # 1. Yazı ve İmleç Boyutları (Uzaktan okuma için)
    echo "1/4: Ölçekleme ve Fontlar büyütülüyor..."
    run_as_user "gsettings set org.gnome.desktop.interface text-scaling-factor 1.5"
    run_as_user "gsettings set org.gnome.desktop.interface cursor-size 48"

    # 2. Dock (Alt Bar) Ayarları
    echo "2/4: Alt Bar (Dock) yapılandırılıyor..."
    # Ubuntu Dock ayarları
    run_as_user "gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'BOTTOM'"
    run_as_user "gsettings set org.gnome.shell.extensions.dash-to-dock dash-max-icon-size 64"
    run_as_user "gsettings set org.gnome.shell.extensions.dash-to-dock extend-height false"
    run_as_user "gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed true"
    run_as_user "gsettings set org.gnome.shell.extensions.dash-to-dock transparency-mode 'FIXED'"
    
    # 3. Uygulama Sabitleme (Dock'a Ekleme)
    echo "3/4: Uygulamalar Dock'a sabitleniyor..."
    
    # Uygulamaların .desktop dosya isimlerini tespit etmeye çalış
    APPS="['org.gnome.Nautilus.desktop', 'org.gnome.Settings.desktop']"
    
    # Kodi var mı?
    if [ -f /usr/share/applications/kodi.desktop ]; then
        APPS="${APPS%,*}, 'kodi.desktop']"
    fi
    
    # Chrome/Chromium/Firefox tespiti
    if [ -f /usr/share/applications/google-chrome.desktop ]; then
        APPS="${APPS%,*}, 'google-chrome.desktop']"
    elif [ -f /usr/share/applications/google-chrome-stable.desktop ]; then
        APPS="${APPS%,*}, 'google-chrome-stable.desktop']"
    elif [ -f /usr/share/applications/firefox.desktop ]; then
        APPS="${APPS%,*}, 'firefox.desktop']"
    fi
    
    # VLC
    if [ -f /usr/share/applications/vlc.desktop ]; then
        APPS="${APPS%,*}, 'vlc.desktop']"
    fi

    # Komutu uygula
    run_as_user "gsettings set org.gnome.shell favorite-apps \"$APPS\""

    # 4. Güç ve Ekran Koruyucu (TV kapanmasın)
    echo "4/4: Uyku modları kapatılıyor..."
    run_as_user "gsettings set org.gnome.desktop.session idle-delay 0"
    
    echo "--- TV Modu Başarıyla Uygulandı! ---"
}

# -- 5. PC MODUNA DÖNÜŞ (RESET) --
disable_tv_mode() {
    echo "--- PC Moduna Dönülüyor (Fabrika Ayarları) ---"
    run_as_user "gsettings set org.gnome.desktop.interface text-scaling-factor 1.0"
    run_as_user "gsettings set org.gnome.desktop.interface cursor-size 24"
    run_as_user "gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'LEFT'"
    run_as_user "gsettings set org.gnome.shell.extensions.dash-to-dock dash-max-icon-size 48"
    run_as_user "gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false"
    run_as_user "gsettings set org.gnome.shell.extensions.dash-to-dock extend-height true"
    run_as_user "gsettings set org.gnome.desktop.session idle-delay 300"
    echo "--- PC Moduna Dönüldü ---"
}

# -- MENÜ --
clear
echo "=========================================="
echo "   UBUNTU TV DÖNÜŞTÜRÜCÜ (COUCH MODE)"
echo "=========================================="
echo "1. TV Modunu Etkinleştir (Büyük Yazılar + Alt Dock + Kodi)"
echo "2. PC Moduna Geri Dön (Varsayılan)"
echo "3. Çıkış"
echo ""
read -p "Seçiminiz (1-3): " choice

case $choice in
    1)
        install_apps
        enable_tv_mode
        echo ""
        echo "Değişikliklerin tam görünmesi için sistemi yeniden başlatmanız önerilir."
        read -p "Şimdi yeniden başlatılsın mı? (e/h): " reboot_ans
        if [[ "$reboot_ans" == "e" || "$reboot_ans" == "E" ]]; then
            reboot
        fi
        ;;
    2)
        disable_tv_mode
        ;;
    3)
        exit 0
        ;;
    *)
        echo "Geçersiz seçim."
        ;;
esac
