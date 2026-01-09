#!/usr/bin/env bash

# -- KENDİNİ DÜZELTME VE YETKİ YÜKSELTME --
# 1. DOS/Windows satır sonu hatalarını temizle
sed -i 's/\r$//' "$0" 2>/dev/null

# 2. Root yetkisi kontrolü ve otomatik yükseltme (Çift tıklama desteği için)
if [[ $EUID -ne 0 ]]; then
    # Eğer root değilse, kullanıcıya bilgi ver ve sudo ile yeniden başlat
    if command -v whiptail &>/dev/null; then
        whiptail --title "Yönetici İzni Gerekiyor" --msgbox "Bu kurulum sistemi yapılandırmak için yönetici (sudo) yetkisine ihtiyaç duyar.\n\nTamam'a bastıktan sonra parolanızı girmeniz istenecektir." 12 60
    else
        echo "Yönetici (sudo) yetkisi gerekiyor. Parolanız istenecek..."
    fi
    
    # Betiği sudo ile yeniden çalıştır
    sudo "$0" "$@"
    exit $?
fi

##############################################
# MiniPC → TV-Box Ultimate Kurulum Aracı
#
# Sürüm 5.0 (Tam Kapsamlı Linux Sürümü)
#
# Özellikler:
# - Tüm Araçlar (OBS, Torrent, LocalSend, Cloud vb.)
# - Whiptail GUI (Kolay Seçim)
# - Otomatik Config Oluşturma
# - Helper Scriptler
# - Çift Tıklama Desteği
##############################################

# -- SABİTLER VE DEĞİŞKENLER --
# Gerçek kullanıcıyı bul (Dosyaları /root yerine kullanıcıya kaydetmek için)
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# -- RENK KODLARI --
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -- LOG FONKSİYONLARI --
log_info() { echo -e "${BLUE}[BİLGİ]${NC} $1"; }
log_success() { echo -e "${GREEN}[BAŞARILI]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[UYARI]${NC} $1"; }
log_error() { echo -e "${RED}[HATA]${NC} $1"; }

# -- TEMEL BAĞIMLILIKLAR --
log_info "Temel bağımlılıklar kontrol ediliyor..."
apt update
apt install -y whiptail curl gpg software-properties-common apt-transport-https wget git build-essential unzip

##############################################
# -- FONKSİYONLAR --
##############################################

# --- 1. Paket Yöneticileri ---
install_flatpak() {
    log_info "Flatpak ve Flathub kuruluyor..."
    apt install -y flatpak gnome-software-plugin-flatpak
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    log_success "Flatpak hazır."
}

# --- 2. Medya Oynatıcılar ---
install_kodi() {
    log_info "Kodi ve IPTV eklentileri kuruluyor..."
    apt install -y kodi kodi-inputstream-adaptive kodi-inputstream-rtmp kodi-pvr-iptvsimple
    
    # -- KODI GELİŞMİŞ AYARLAR --
    log_info "Kodi performans ayarları yapılıyor..."
    mkdir -p "$REAL_HOME/.kodi/userdata"
    cat > "$REAL_HOME/.kodi/userdata/advancedsettings.xml" <<EOF
<advancedsettings>
  <network>
    <buffermode>1</buffermode>
    <cachemembuffersize>209715200</cachemembuffersize>
    <readbufferfactor>4.0</readbufferfactor>
  </network>
  <video>
    <busydialogdelayms>0</busydialogdelayms>
  </video>
</advancedsettings>
EOF
    
    # -- IPTV AYARLARI --
    mkdir -p "$REAL_HOME/.kodi/userdata/addon_data/pvr.iptvsimple"
    mkdir -p "$REAL_HOME/.kodi/iptv"
    
    # Örnek IPTV Listesi
    wget -qO "$REAL_HOME/.kodi/iptv/channels.m3u" https://iptv-org.github.io/iptv/countries/tr.m3u || echo "#EXTM3U" > "$REAL_HOME/.kodi/iptv/channels.m3u"
    chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.kodi"
}

install_mpv() {
    log_info "MPV kuruluyor..."
    apt install -y mpv
    # -- MPV CONF (TV için Optimize) --
    mkdir -p "$REAL_HOME/.config/mpv"
    cat > "$REAL_HOME/.config/mpv/mpv.conf" <<EOF
profile=gpu-hq
vo=gpu
hwdec=auto-safe
fullscreen=yes
osd-font-size=32
EOF
    chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/mpv"
}

install_vlc() {
    apt install -y vlc vlc-plugin-notify
}

install_jellyfin() {
    install_flatpak
    flatpak install -y flathub com.github.iwalton3.jellyfin-media-player
}

install_stremio() {
    log_info "Stremio indiriliyor..."
    wget -O /tmp/stremio.deb https://dl.strem.io/linux/v4.4.168/stremio_4.4.168-1_amd64.deb
    apt install -y /tmp/stremio.deb
    rm -f /tmp/stremio.deb
}

# --- 3. Codec ve Hızlandırma ---
install_codecs_hw() {
    log_info "Codec ve Donanım Hızlandırma kuruluyor..."
    apt install -y ubuntu-restricted-extras libavcodec-extra ffmpeg
    apt install -y intel-media-va-driver i965-va-driver vainfo mesa-va-drivers mesa-vdpau-drivers vdpauinfo
    
    # Tearing Fix
    if ! grep -q "TearFree" /etc/X11/xorg.conf.d/* 2>/dev/null; then
        mkdir -p /etc/X11/xorg.conf.d
        cat > /etc/X11/xorg.conf.d/20-intel.conf <<EOF
Section "Device"
    Identifier "Intel Graphics"
    Driver "intel"
    Option "TearFree" "true"
EndSection
EOF
    fi
}

# --- 4. Oyun ---
install_gaming_pack() {
    log_info "Oyun paketleri kuruluyor (Steam, Retroarch, Moonlight)..."
    # Steam
    wget -O /tmp/steam.deb https://cdn.akamai.steamstatic.com/client/installer/steam.deb
    apt install -y /tmp/steam.deb
    rm /tmp/steam.deb
    # Emülatörler
    apt install -y retroarch
    # Moonlight
    install_flatpak
    flatpak install -y flathub com.moonlight_stream.Moonlight
    # Bluetooth Gamepad
    apt install -y bluez blueman joystick xboxdrv
    udevadm control --reload-rules
}

# --- 5. Android (Waydroid) ---
install_waydroid() {
    log_info "Waydroid (Android) hazırlanıyor..."
    export DISTRO="ubuntu"
    curl -sS https://repo.waydro.id/waydro.id.gpg | gpg --dearmor -o /usr/share/keyrings/waydro.id-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/waydro.id-archive-keyring.gpg] https://repo.waydro.id/ $DISTRO main" | tee /etc/apt/sources.list.d/waydroid.list
    apt update
    apt install -y waydroid
    
    # Helper Script
    cat > "$REAL_HOME/Desktop/waydroid-baslat.sh" <<EOF
#!/bin/bash
sudo systemctl start waydroid-container
waydroid session start &
sleep 3
waydroid show-full-ui
EOF
    chmod +x "$REAL_HOME/Desktop/waydroid-baslat.sh"
    chown "$REAL_USER:$REAL_USER" "$REAL_HOME/Desktop/waydroid-baslat.sh"
}

# --- 6. Araçlar ve Sistem ---
install_system_tools() {
    log_info "Sistem araçları kuruluyor..."
    apt install -y htop btop neofetch curl git cec-utils
    
    # CEC Test Scripti
    cat > "$REAL_HOME/Desktop/cec-test.sh" <<EOF
#!/bin/bash
echo "scan" | cec-client -s -d 1
EOF
    chmod +x "$REAL_HOME/Desktop/cec-test.sh"
    chown "$REAL_USER:$REAL_USER" "$REAL_HOME/Desktop/cec-test.sh"
    
    # Overscan Scripti
    cat > "$REAL_HOME/Desktop/fix-overscan.sh" <<EOF
#!/bin/bash
# xrandr --output HDMI-1 --set "underscan" on --set "underscan hborder" 40 --set "underscan vborder" 25
echo "Scripti düzenleyin."
EOF
    chmod +x "$REAL_HOME/Desktop/fix-overscan.sh"
    chown "$REAL_USER:$REAL_USER" "$REAL_HOME/Desktop/fix-overscan.sh"
}

install_webmin_docker() {
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker "$REAL_USER"
    wget -qO- http://www.webmin.com/jcameron-key.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/webmin.gpg
    echo "deb https://download.webmin.com/download/repository sarge contrib" | tee /etc/apt/sources.list.d/webmin.list
    apt update
    apt install -y webmin
}

install_browsers() {
    wget -qO /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    apt install -y /tmp/chrome.deb
    apt install -y firefox
}

install_network_sharing() {
    apt install -y samba samba-common-bin
    if ! grep -q "TVBox-Share" /etc/samba/smb.conf; then
        cat >> /etc/samba/smb.conf <<EOF

[TVBox-Share]
   path = /home/$REAL_USER/Videos
   browseable = yes
   read only = no
   guest ok = yes
EOF
        systemctl restart smbd
    fi
}

install_tailscale() {
    log_info "Tailscale VPN kuruluyor..."
    curl -fsSL https://tailscale.com/install.sh | sh
}

install_localsend() {
    log_info "LocalSend kuruluyor..."
    snap install localsend
}

install_obs() {
    log_info "OBS Studio kuruluyor..."
    add-apt-repository ppa:obsproject/obs-studio -y
    apt update
    apt install -y obs-studio ffmpeg
}

install_torrent() {
    log_info "Transmission Torrent İstemcisi kuruluyor..."
    apt install -y transmission-gtk
}

install_cloud_sync() {
    log_info "Rclone (Cloud Sync) kuruluyor..."
    apt install -y rclone
}

install_autologin() {
    if [ -f /etc/gdm3/custom.conf ]; then
        sed -i "s/^#.*AutomaticLoginEnable.*/AutomaticLoginEnable = true/" /etc/gdm3/custom.conf
        sed -i "s/^#.*AutomaticLogin.*/AutomaticLogin = $REAL_USER/" /etc/gdm3/custom.conf
    fi
    if [ -f /etc/lightdm/lightdm.conf ]; then
         sed -i "s/^#autologin-user=.*/autologin-user=$REAL_USER/" /etc/lightdm/lightdm.conf
    fi
}

##############################################
# -- MENÜ VE ÇALIŞTIRMA MANTIĞI --
##############################################

# Ana Menü
OPERATION=$(whiptail --title "MiniPC TV-Box Ultimate Kurulum (v5.0)" --menu "İşlem Seçiniz:" 15 60 3 \
"INSTALL" "Kurulum Menüsü (Paket Seçimi)" \
"REMOVE"  "Kaldırma Menüsü" \
"EXIT"    "Çıkış" 3>&1 1>&2 2>&3)

if [[ $? != 0 || "$OPERATION" == "EXIT" ]]; then
    exit 0
fi

# Genişletilmiş Çoklu Seçim Menüsü
CHOICES=$(whiptail --title "Tam Kapsamlı Paket Seçimi" --checklist \
"Kurulacak bileşenleri seçiniz (Space ile işaretle):" 22 78 14 \
"UPDATE" "Sistem Güncelleme & Temel Araçlar" ON \
"KODI" "Kodi (IPTV + Performans Ayarlı)" ON \
"VLC_MPV" "VLC ve MPV (TV Ayarlı)" ON \
"CODECS" "Tüm Codec ve Sürücüler (Intel/AMD/Nvidia)" ON \
"STREMIO" "Stremio (Film/Dizi)" OFF \
"JELLYFIN" "Jellyfin Client" OFF \
"BROWSERS" "Chrome ve Firefox" ON \
"GAMING" "Steam, Retroarch, Moonlight, Gamepad" OFF \
"WAYDROID" "Android Desteği (Waydroid)" OFF \
"SYSTEM_TOOLS" "Overscan/CEC Araçları, Htop" ON \
"NETWORK_SHARE" "Samba Ağ Paylaşımı" OFF \
"TAILSCALE" "Tailscale VPN" OFF \
"LOCALSEND" "LocalSend (Dosya Transferi)" ON \
"OBS" "OBS Studio (Ekran Kaydı/Yayın)" OFF \
"TORRENT" "Transmission (Torrent İstemcisi)" OFF \
"CLOUD_SYNC" "Rclone (Bulut Senkronizasyon)" OFF \
"WEBMIN_DOCKER" "Webmin ve Docker" OFF \
"AUTOLOGIN" "Otomatik Oturum Açma" ON \
"FLATPAK" "Flatpak Desteği" ON \
3>&1 1>&2 2>&3)

if [[ $? != 0 ]]; then
    exit 0
fi

# Seçimleri Uygula
if [[ "$OPERATION" == "INSTALL" ]]; then
    for choice in $CHOICES; do
        case $choice in
            "\"UPDATE\"") apt update && apt upgrade -y && install_system_tools ;;
            "\"FLATPAK\"") install_flatpak ;;
            "\"KODI\"") install_kodi ;;
            "\"VLC_MPV\"") install_vlc; install_mpv ;;
            "\"CODECS\"") install_codecs_hw ;;
            "\"STREMIO\"") install_stremio ;;
            "\"JELLYFIN\"") install_jellyfin ;;
            "\"BROWSERS\"") install_browsers ;;
            "\"GAMING\"") install_gaming_pack ;;
            "\"WAYDROID\"") install_waydroid ;;
            "\"SYSTEM_TOOLS\"") install_system_tools ;;
            "\"NETWORK_SHARE\"") install_network_sharing ;;
            "\"TAILSCALE\"") install_tailscale ;;
            "\"LOCALSEND\"") install_localsend ;;
            "\"OBS\"") install_obs ;;
            "\"TORRENT\"") install_torrent ;;
            "\"CLOUD_SYNC\"") install_cloud_sync ;;
            "\"WEBMIN_DOCKER\"") install_webmin_docker ;;
            "\"AUTOLOGIN\"") install_autologin ;;
        esac
    done
    
    # Temizlik
    apt autoremove -y
    apt clean
    
    whiptail --title "Tamamlandı" --msgbox "Seçilen işlemler başarıyla tamamlandı!\n\nDeğişikliklerin etkili olması için sistemi yeniden başlatmanız önerilir.\n\nKomut: sudo reboot" 12 60

elif [[ "$OPERATION" == "REMOVE" ]]; then
    for choice in $CHOICES; do
        case $choice in
            "\"KODI\"") apt purge -y kodi* ;;
            "\"VLC_MPV\"") apt purge -y vlc mpv ;;
            "\"BROWSERS\"") apt purge -y google-chrome-stable firefox ;;
            "\"GAMING\"") apt purge -y steam-installer retroarch ;;
            "\"WAYDROID\"") apt purge -y waydroid ;;
            "\"OBS\"") apt purge -y obs-studio ;;
            "\"LOCALSEND\"") snap remove localsend ;;
            "\"TORRENT\"") apt purge -y transmission-gtk ;;
            "\"CLOUD_SYNC\"") apt purge -y rclone ;;
            "\"WEBMIN_DOCKER\"") apt purge -y webmin docker-ce ;;
        esac
    done
    whiptail --msgbox "Seçilen paketler kaldırıldı." 10 60
fi

exit 0
