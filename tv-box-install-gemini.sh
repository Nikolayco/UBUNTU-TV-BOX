#!/usr/bin/env bash

# =================================================================
# MiniPC -> TV-Box MASTERPIECE SÜRÜM v7.0
#
# Birleştirilen Özellikler:
# - ARAYÜZ: Gemini'nin Whiptail Görsel Menüsü
# - GÜVENLİK: Claude'un VNC Şifreleme ve Firewall Kuralları
# - HATA YÖNETİMİ: Claude'un Trap ve Cleanup fonksiyonları
# - KAPSAM: Tüm paketler tek çatı altında
# =================================================================

# -- AYARLAR VE HATA YÖNETİMİ (CLAUDE MOTORU) --
set -u # Tanımsız değişken hatası ver
# Not: set -e'yi whiptail iptalleri için esnetiyoruz ama trap kullanıyoruz.

# Hata yakalama fonksiyonu
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo -e "\033[0;31m[HATA] Bir sorun oluştu! Çıkış kodu: $exit_code\033[0m"
    fi
}
trap cleanup EXIT

# 1. DOS/Windows satır sonu temizliği
sed -i 's/\r$//' "$0" 2>/dev/null

# 2. Root Yetkisi Kontrolü
if [[ $EUID -ne 0 ]]; then
    if command -v whiptail &>/dev/null; then
        whiptail --title "Yönetici İzni" --msgbox "Bu işlem sudo yetkisi gerektirir. Parolanız istenecek." 10 60
    else
        echo "Root yetkisi gerekiyor..."
    fi
    sudo "$0" "$@"
    exit $?
fi

# -- DEĞİŞKENLER --
REAL_USER=${SUDO_USER:-$USER}
if [ "$REAL_USER" = "root" ]; then
    REAL_HOME="/root"
    echo "UYARI: Root kullanıcısı ile işlem yapılıyor."
else
    REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
fi

# -- RENKLER --
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# -- LOGLAMA --
log_info() { echo -e "${BLUE}[BİLGİ]${NC} $1"; }
log_success() { echo -e "${GREEN}[BAŞARILI]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[UYARI]${NC} $1"; }

# -- SİSTEM SAĞLIĞI KONTROLÜ (GELİŞMİŞ) --
check_system_health() {
    log_info "Sistem sağlığı ve güvenlik kontrolleri..."
    
    # İnternet
    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        whiptail --title "Hata" --msgbox "İnternet bağlantısı yok! Lütfen ağı kontrol edin." 10 60
        exit 1
    fi

    # Disk Alanı
    FREE_SPACE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$FREE_SPACE" -lt 15 ]; then
        whiptail --title "Uyarı" --yesno "Disk alanı düşük ($FREE_SPACE GB). En az 15GB önerilir. Devam edilsin mi?" 10 60
        if [ $? -ne 0 ]; then exit 0; fi
    fi
    
    # Bağımlılıklar
    apt update
    apt install -y whiptail curl gpg software-properties-common apt-transport-https wget git build-essential unzip
}

##############################################
# -- FONKSİYONLAR --
##############################################

install_flatpak() {
    log_info "Flatpak altyapısı kuruluyor..."
    apt install -y flatpak gnome-software-plugin-flatpak
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
}

install_media_bundle() {
    log_info "Medya paketi (VLC, MPV, Codecs) kuruluyor..."
    apt install -y vlc vlc-plugin-notify mpv ubuntu-restricted-extras libavcodec-extra ffmpeg
    
    # MPV Optimize Ayarlar
    mkdir -p "$REAL_HOME/.config/mpv"
    cat > "$REAL_HOME/.config/mpv/mpv.conf" <<EOF
profile=gpu-hq
vo=gpu
hwdec=auto-safe
fullscreen=yes
EOF
    chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/mpv"
}

install_kodi_iptv() {
    log_info "Kodi, IPTV ve Hypnotix kuruluyor..."
    apt install -y kodi kodi-inputstream-adaptive kodi-inputstream-rtmp kodi-pvr-iptvsimple hypnotix
    
    # Kodi Performans Ayarı
    mkdir -p "$REAL_HOME/.kodi/userdata"
    cat > "$REAL_HOME/.kodi/userdata/advancedsettings.xml" <<EOF
<advancedsettings>
  <network>
    <buffermode>1</buffermode>
    <cachemembuffersize>209715200</cachemembuffersize>
    <readbufferfactor>4.0</readbufferfactor>
  </network>
</advancedsettings>
EOF
    chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.kodi"
}

install_spotify() {
    log_info "Spotify kuruluyor..."
    curl -sS https://download.spotify.com/debian/pubkey_7A3A762FAFD4A51F.gpg | sudo gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg
    echo "deb http://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list
    apt update
    apt install -y spotify-client
}

install_audio_enhancements() {
    log_info "Ses iyileştirmeleri (PulseAudio/PipeWire)..."
    apt install -y pulseaudio pavucontrol
    apt install -y easyeffects 2>/dev/null || apt install -y pulseeffects
}

install_browsers() {
    log_info "Tarayıcılar kuruluyor..."
    wget -qO /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    apt install -y /tmp/chrome.deb
    rm /tmp/chrome.deb
    apt install -y firefox
}

install_gaming() {
    log_info "Oyun paketi (Steam, Retroarch, Gamepad) kuruluyor..."
    
    # Steam
    wget -qO /tmp/steam.deb https://cdn.akamai.steamstatic.com/client/installer/steam.deb
    apt install -y /tmp/steam.deb
    rm /tmp/steam.deb
    
    # Diğerleri
    apt install -y retroarch bluez blueman joystick xboxdrv
    
    # Bluetooth Gamepad Fix (Claude'dan alındı)
    sed -i 's/#AutoEnable=false/AutoEnable=true/' /etc/bluetooth/main.conf
    systemctl restart bluetooth
}

# -- GÜVENLİ VNC KURULUMU (CLAUDE ÖZELLİĞİ) --
install_secure_vnc() {
    log_info "Güvenli X11VNC kuruluyor..."
    apt install -y x11vnc openssh-server
    
    # Rastgele Şifre Oluşturma
    VNC_PASS=$(openssl rand -base64 12)
    mkdir -p "$REAL_HOME/.vnc"
    x11vnc -storepasswd "$VNC_PASS" "$REAL_HOME/.vnc/passwd"
    chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.vnc"
    
    # Servis Oluşturma
    cat > /etc/systemd/system/x11vnc.service <<EOF
[Unit]
Description=X11VNC Server
After=display-manager.service

[Service]
Type=simple
ExecStart=/usr/bin/x11vnc -forever -loop -auth guess -rfbauth $REAL_HOME/.vnc/passwd -rfbport 5900
User=$REAL_USER
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable x11vnc
    systemctl start x11vnc
    
    # Firewall Ayarı (Güvenlik)
    if command -v ufw &>/dev/null; then
        ufw allow from 192.168.0.0/16 to any port 5900
        ufw --force enable
    fi

    # Şifreyi Kaydet
    echo "$VNC_PASS" > "$REAL_HOME/Desktop/vnc-sifresi.txt"
    chown "$REAL_USER:$REAL_USER" "$REAL_HOME/Desktop/vnc-sifresi.txt"
    log_success "VNC Şifresi Masaüstüne kaydedildi: vnc-sifresi.txt"
}

install_webmin_docker() {
    log_info "Webmin ve Docker kuruluyor..."
    
    # Docker
    if ! command -v docker &>/dev/null; then
        curl -fsSL https://get.docker.com | sh
        usermod -aG docker "$REAL_USER"
    fi

    # Webmin (Repo Fix)
    if ! command -v webmin &>/dev/null; then
        curl -o setup-repos.sh https://raw.githubusercontent.com/webmin/webmin/master/setup-repos.sh
        sh setup-repos.sh
        apt install -y webmin
    fi
}

install_performance() {
    log_info "Performans optimizasyonu..."
    apt install -y preload cpufrequtils
    if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
        echo "vm.swappiness=10" >> /etc/sysctl.conf
        sysctl -p
    fi
}

install_tools() {
    apt install -y htop btop neofetch curl git cec-utils
    
    # Overscan Script
    cat > "$REAL_HOME/Desktop/fix-overscan.sh" <<EOF
#!/bin/bash
# xrandr --output HDMI-1 --set "underscan" on --set "underscan hborder" 40 --set "underscan vborder" 25
echo "Bu dosyanın içini kendi ekranınıza göre düzenleyin"
EOF
    chmod +x "$REAL_HOME/Desktop/fix-overscan.sh"
    chown "$REAL_USER:$REAL_USER" "$REAL_HOME/Desktop/fix-overscan.sh"
}

install_tailscale() {
    log_info "Tailscale VPN kuruluyor..."
    curl -fsSL https://tailscale.com/install.sh | sh
    systemctl enable --now tailscaled
}

##############################################
# -- ANA MENÜ (WHIPTAIL) --
##############################################

check_system_health

CHOICES=$(whiptail --title "MiniPC Masterpiece Setup v7.0" --checklist \
"Kurulacak bileşenleri seçiniz (Space ile işaretle):" 24 78 16 \
"UPDATE" "Sistem Güncelleme & Temel Araçlar" ON \
"MEDIA" "VLC, MPV, Codecs (Medya)" ON \
"KODI" "Kodi & Hypnotix IPTV" ON \
"SPOTIFY" "Spotify Müzik" ON \
"AUDIO" "Ses Geliştirme & Ekolayzer" OFF \
"BROWSERS" "Chrome & Firefox" ON \
"GAMING" "Steam, Retroarch & Gamepad" OFF \
"VNC_SEC" "Güvenli Uzaktan Erişim (VNC+Firewall)" OFF \
"TAILSCALE" "Tailscale VPN" OFF \
"WEBMIN" "Webmin & Docker (Sunucu)" OFF \
"PERFORMANCE" "RAM & CPU Optimizasyonu" ON \
"TOOLS" "Sistem Araçları (Htop, CEC, Overscan)" ON \
"FLATPAK" "Flatpak Desteği" ON \
3>&1 1>&2 2>&3)

if [[ $? != 0 ]]; then
    echo "İşlem kullanıcı tarafından iptal edildi."
    exit 0
fi

# Kurulum Döngüsü
for choice in $CHOICES; do
    case $choice in
        "\"UPDATE\"") apt update && apt upgrade -y ;;
        "\"MEDIA\"") install_media_bundle ;;
        "\"KODI\"") install_kodi_iptv ;;
        "\"SPOTIFY\"") install_spotify ;;
        "\"AUDIO\"") install_audio_enhancements ;;
        "\"BROWSERS\"") install_browsers ;;
        "\"GAMING\"") install_gaming ;;
        "\"VNC_SEC\"") install_secure_vnc ;;
        "\"TAILSCALE\"") install_tailscale ;;
        "\"WEBMIN\"") install_webmin_docker ;;
        "\"PERFORMANCE\"") install_performance ;;
        "\"TOOLS\"") install_tools ;;
        "\"FLATPAK\"") install_flatpak ;;
    esac
done

# Temizlik
apt autoremove -y
apt clean

whiptail --title "Tamamlandı" --msgbox "Masterpiece Kurulumu başarıyla tamamlandı!\n\nÖNEMLİ:\n1. VNC kurduysanız şifre masaüstünde 'vnc-sifresi.txt' dosyasına kaydedildi.\n2. Lütfen sistemi yeniden başlatın.\n\nKomut: sudo reboot" 15 70
