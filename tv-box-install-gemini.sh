#!/usr/bin/env bash

# -- AYARLAR --
set -u
# Hata olduğunda durdurma, devam et (Görsel ayarlar bazen hata verebilir)
set +e

# 1. Root Kontrolü (Sudo ile çalıştırılmalı)
if [[ $EUID -ne 0 ]]; then
    echo "Bu scripti çalıştırmak için sudo yetkisi gerekir."
    sudo "$0" "$@"
    exit $?
fi

# -- DEĞİŞKENLER --
REAL_USER=${SUDO_USER:-$USER}
if [ "$REAL_USER" = "root" ]; then
    echo "HATA: Bu script root kullanıcısı ile değil, normal kullanıcı ile (sudo kullanarak) çalıştırılmalı."
    echo "Çünkü arayüz ayarları kullanıcının hesabına yapılmalı."
    exit 1
fi
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# -- RENKLER --
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }

##############################################
# 1. UYGULAMA KURULUMLARI (Dock için gerekli)
##############################################
install_essentials() {
    log_info "Temel TV uygulamaları kuruluyor..."
    apt update
    apt install -y kodi vlc google-chrome-stable 2>/dev/null || apt install -y chromium-browser
    apt install -y gnome-shell-extension-prefs dconf-cli uuid-runtime
    
    # Kısayollar için gerekli klasör
    mkdir -p "$REAL_HOME/.local/share/applications"
}

##############################################
# 2. TV ARAYÜZ DÖNÜŞÜMÜ (SIHİR BURADA)
##############################################
transform_to_tv_ui() {
    log_info "Ubuntu TV Arayüzüne dönüştürülüyor..."

    # Bu komutları gerçek kullanıcı adına çalıştırmalıyız
    # DBUS adresini bulmak için ufak bir hack (GNOME ayarlarını değiştirmek için şart)
    PID=$(pgrep -u "$REAL_USER" gnome-session | head -n 1)
    export DBUS_SESSION_BUS_ADDRESS=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/"$PID"/environ|cut -d= -f2-)

    # --- A. GÖRÜNÜM ÖLÇEKLEME (Yazıları Büyüt) ---
    log_info "Ekran ve Yazı ölçeklemesi ayarlanıyor (Uzaktan okuma için)..."
    sudo -u "$REAL_USER" gsettings set org.gnome.desktop.interface text-scaling-factor 1.5
    sudo -u "$REAL_USER" gsettings set org.gnome.desktop.interface cursor-size 48

    # --- B. DOCK (ALT MENÜ) AYARLARI ---
    log_info "Dock (Alt Menü) Android TV stiline getiriliyor..."
    
    # Dock'u Alta Al
    sudo -u "$REAL_USER" gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'BOTTOM'
    
    # İkonları Devasa Yap (TV için 64-96px idealdir)
    sudo -u "$REAL_USER" gsettings set org.gnome.shell.extensions.dash-to-dock dash-max-icon-size 84
    
    # Dock Her Zaman Görünür Olsun (Android TV menüsü gibi)
    sudo -u "$REAL_USER" gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed true
    sudo -u "$REAL_USER" gsettings set org.gnome.shell.extensions.dash-to-dock extend-height false
    
    # Saydamlık Ayarı (Daha modern dursun)
    sudo -u "$REAL_USER" gsettings set org.gnome.shell.extensions.dash-to-dock transparency-mode 'FIXED'
    sudo -u "$REAL_USER" gsettings set org.gnome.shell.extensions.dash-to-dock background-opacity 0.8

    # --- C. DOCK'A UYGULAMALARI SABİTLE ---
    log_info "Dock'a Kodi, Web ve Medya uygulamaları sabitleniyor..."
    
    # Hangi uygulamalar varsa onları ekle
    APPS="['kodi.desktop', 'google-chrome.desktop', 'firefox.desktop', 'vlc.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Settings.desktop']"
    
    sudo -u "$REAL_USER" gsettings set org.gnome.shell.favorite-apps "$APPS"

    # --- D. TEMİZLİK (Masaüstü İkonlarını Gizle) ---
    log_info "Masaüstü temizleniyor..."
    # Ubuntu sürümüne göre komut değişebilir, ikisini de deniyoruz
    sudo -u "$REAL_USER" gsettings set org.gnome.shell.extensions.ding show-home false 2>/dev/null
    sudo -u "$REAL_USER" gsettings set org.gnome.desktop.background show-desktop-icons false 2>/dev/null

    # --- E. GÜÇ AYARLARI (TV kapanmasın) ---
    log_info "Uyku modları kapatılıyor (TV modu)..."
    sudo -u "$REAL_USER" gsettings set org.gnome.desktop.session idle-delay 0
    sudo -u "$REAL_USER" gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
}

##############################################
# 3. GERİ ALMA (Eski Haline Döndür)
##############################################
revert_to_pc_ui() {
    log_info "PC Moduna geri dönülüyor..."
    sudo -u "$REAL_USER" gsettings set org.gnome.desktop.interface text-scaling-factor 1.0
    sudo -u "$REAL_USER" gsettings set org.gnome.shell.extensions.dash-to-dock dash-max-icon-size 48
    sudo -u "$REAL_USER" gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false
    sudo -u "$REAL_USER" gsettings set org.gnome.desktop.session idle-delay 300
    log_success "Ayarlar sıfırlandı."
}

##############################################
# ANA MENÜ
##############################################

# Whiptail yüklü mü?
if ! command -v whiptail &>/dev/null; then
    apt update && apt install -y whiptail
fi

CHOICE=$(whiptail --title "Ubuntu TV Arayüz Dönüştürücü v8.0" --menu "Seçiminizi Yapın:" 15 60 4 \
"1" "TV Modunu Uygula (Büyük İkonlar, Sabit Dock)" \
"2" "Kodi ve Gerekli Uygulamaları Kur" \
"3" "PC Moduna Geri Dön (Sıfırla)" \
"4" "Çıkış" 3>&1 1>&2 2>&3)

case $CHOICE in
    1)
        transform_to_tv_ui
        whiptail --msgbox "Dönüşüm Tamamlandı!\n\nAlt tarafta büyük bir menü (Dock) göreceksiniz.\nYazılar TV'den okunacak boyuta getirildi.\n\nDeğişikliklerin tam oturması için Oturumu Kapatıp Açın veya Yeniden Başlatın." 12 60
        ;;
    2)
        install_essentials
        whiptail --msgbox "Uygulamalar kuruldu. Şimdi 1. seçeneği kullanarak arayüzü değiştirebilirsiniz." 10 60
        ;;
    3)
        revert_to_pc_ui
        whiptail --msgbox "Ayarlar varsayılan PC moduna döndürüldü." 10 60
        ;;
    4)
        exit 0
        ;;
esac
