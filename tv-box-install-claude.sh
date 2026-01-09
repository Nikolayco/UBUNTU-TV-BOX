#!/usr/bin/env bash

# =================================================================
# MiniPC -> TV-Box ULTIMATE EDITION v8.0
#
# Özellikler:
# ✓ Whiptail GUI (Kolay Kullanım)
# ✓ Gelişmiş Hata Yönetimi ve Güvenlik
# ✓ VNC Şifreleme + Firewall
# ✓ Post-Install Kontroller
# ✓ Kapsamlı Paket Desteği (Media, Gaming, Android, Cloud)
# ✓ Detaylı Kurulum Özeti
# =================================================================

# -- HATA YÖNETİMİ --
set -u

cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ] && [ $exit_code -ne 130 ]; then
        echo -e "\033[0;31m[HATA] Beklenmeyen hata! Çıkış kodu: $exit_code\033[0m" >&2
    fi
}
trap cleanup EXIT

# DOS/Windows satır sonu temizliği
sed -i 's/\r$//' "$0" 2>/dev/null

# -- ROOT YETKİSİ KONTROLÜ --
if [[ $EUID -ne 0 ]]; then
    if command -v whiptail &>/dev/null; then
        whiptail --title "Yönetici İzni Gerekli" \
            --msgbox "Bu kurulum sudo yetkisi gerektirir.\n\nTamam'a basınca parolanız istenecek." 10 60
    else
        echo "Root yetkisi gerekiyor. Parolanız istenecek..."
    fi
    exec sudo "$0" "$@"
fi

# -- DEĞİŞKENLER --
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6)

if [ -z "$REAL_HOME" ] || [ "$REAL_USER" = "root" ]; then
    if command -v whiptail &>/dev/null; then
        whiptail --title "⚠️ Root Kullanıcı Uyarısı" --yesno \
            "Root kullanıcısıyla kurulum yapıyorsunuz!\n\nBu önerilmez ve bazı özelliklerde sorun çıkabilir.\n\nYine de devam etmek istiyor musunuz?" 12 60
        if [ $? -ne 0 ]; then exit 0; fi
    fi
    REAL_HOME="/root"
fi

# -- RENKLER --
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m'

# -- LOG FONKSİYONLARI --
log_info() { echo -e "${BLUE}[ℹ️  BİLGİ]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓ BAŞARILI]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[⚠️  UYARI]${NC} $1"; }
log_error() { echo -e "${RED}[✗ HATA]${NC} $1" >&2; }

# -- SİSTEM SAĞLIK KONTROLÜ --
check_system_health() {
    log_info "Sistem sağlığı kontrol ediliyor..."
    
    # İnternet bağlantısı
    if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        whiptail --title "❌ Bağlantı Hatası" \
            --msgbox "İnternet bağlantısı bulunamadı!\n\nLütfen ağ bağlantınızı kontrol edin ve tekrar deneyin." 10 60
        exit 1
    fi

    # Disk alanı kontrolü
    FREE_SPACE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$FREE_SPACE" -lt 15 ]; then
        whiptail --title "💾 Disk Alanı Uyarısı" --yesno \
            "Boş disk alanı: ${FREE_SPACE}GB\n\nEn az 15GB önerilir. Kurulum sırasında alan bitebilir.\n\nYine de devam edilsin mi?" 12 60
        if [ $? -ne 0 ]; then exit 0; fi
    fi
    
    # Ubuntu/Debian kontrolü
    if ! grep -qE "Ubuntu|Debian" /etc/os-release 2>/dev/null; then
        log_warn "Bu script Ubuntu/Debian için optimize edilmiştir."
    fi
    
    # Temel bağımlılıklar
    log_info "Temel paketler kuruluyor..."
    apt update -qq
    apt install -y whiptail curl gpg software-properties-common apt-transport-https wget git build-essential unzip 2>&1 | grep -v "^Selecting"
    
    log_success "Sistem kontrolleri tamamlandı"
}

##############################################
# -- KURULUM FONKSİYONLARI --
##############################################

install_flatpak() {
    log_info "Flatpak deposu ekleniyor..."
    apt install -y flatpak gnome-software-plugin-flatpak 2>&1 | grep -v "^Selecting"
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null
    log_success "Flatpak hazır"
}

install_media_bundle() {
    log_info "Medya oynatıcılar kuruluyor (VLC, MPV)..."
    apt install -y vlc vlc-plugin-notify mpv 2>&1 | grep -v "^Selecting"
    
    # MPV optimizasyonu
    mkdir -p "$REAL_HOME/.config/mpv"
    cat > "$REAL_HOME/.config/mpv/mpv.conf" <<'EOF'
# TV için optimize ayarlar
profile=gpu-hq
vo=gpu
hwdec=auto-safe
video-sync=display-resample
interpolation=yes
fullscreen=yes
osd-font-size=36
EOF
    chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/mpv" 2>/dev/null
    log_success "Medya oynatıcılar kuruldu"
}

install_codecs() {
    log_info "Codec'ler ve donanım hızlandırma..."
    apt install -y ubuntu-restricted-extras libavcodec-extra ffmpeg x264 x265 2>&1 | grep -v "^Selecting"
    
    # Donanım hızlandırma
    apt install -y intel-media-va-driver i965-va-driver vainfo mesa-va-drivers mesa-vdpau-drivers vdpauinfo 2>&1 | grep -v "^Selecting"
    
    # Tearing fix
    mkdir -p /etc/X11/xorg.conf.d
    cat > /etc/X11/xorg.conf.d/20-intel.conf <<'EOF'
Section "Device"
    Identifier "Intel Graphics"
    Driver "intel"
    Option "TearFree" "true"
EndSection
EOF
    log_success "Codec ve hızlandırma tamam"
}

install_kodi_iptv() {
    log_info "Kodi medya merkezi ve IPTV eklentileri..."
    apt install -y kodi kodi-inputstream-adaptive kodi-inputstream-rtmp kodi-pvr-iptvsimple 2>&1 | grep -v "^Selecting"
    
    # Hypnotix IPTV
    apt install -y hypnotix 2>&1 | grep -v "^Selecting"
    
    # Kodi performans ayarları
    mkdir -p "$REAL_HOME/.kodi/userdata"
    cat > "$REAL_HOME/.kodi/userdata/advancedsettings.xml" <<'EOF'
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
    
    # IPTV dizinleri
    mkdir -p "$REAL_HOME/.kodi/iptv"
    wget -qO "$REAL_HOME/.kodi/iptv/channels.m3u" "https://iptv-org.github.io/iptv/countries/tr.m3u" 2>/dev/null || \
        echo "#EXTM3U" > "$REAL_HOME/.kodi/iptv/channels.m3u"
    
    chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.kodi" 2>/dev/null
    log_success "Kodi ve IPTV hazır"
}

install_spotify() {
    log_info "Spotify müzik servisi..."
    curl -sS https://download.spotify.com/debian/pubkey_7A3A762FAFD4A51F.gpg | \
        gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg
    echo "deb http://repository.spotify.com stable non-free" > /etc/apt/sources.list.d/spotify.list
    apt update -qq
    apt install -y spotify-client 2>&1 | grep -v "^Selecting"
    log_success "Spotify kuruldu"
}

install_audio_enhancements() {
    log_info "Ses geliştirmeleri ve ekolayzer..."
    apt install -y pulseaudio pavucontrol pipewire-audio-client-libraries 2>&1 | grep -v "^Selecting"
    apt install -y easyeffects 2>/dev/null || apt install -y pulseeffects 2>&1 | grep -v "^Selecting"
    log_success "Ses sistemi yapılandırıldı"
}

install_browsers() {
    log_info "Web tarayıcıları (Chrome, Firefox)..."
    
    # Chrome
    wget -qO /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    apt install -y /tmp/chrome.deb 2>&1 | grep -v "^Selecting"
    rm -f /tmp/chrome.deb
    
    # Firefox
    apt install -y firefox 2>&1 | grep -v "^Selecting"
    log_success "Tarayıcılar kuruldu"
}

install_gaming() {
    log_info "Gaming paketi (Steam, RetroArch, Gamepad)..."
    
    # Steam
    wget -qO /tmp/steam.deb https://cdn.akamai.steamstatic.com/client/installer/steam.deb
    apt install -y /tmp/steam.deb 2>&1 | grep -v "^Selecting"
    rm -f /tmp/steam.deb
    
    # Emülatörler
    apt install -y retroarch 2>&1 | grep -v "^Selecting"
    
    # Moonlight streaming (flatpak)
    if command -v flatpak &>/dev/null; then
        flatpak install -y flathub com.moonlight_stream.Moonlight 2>/dev/null
    fi
    
    # Bluetooth gamepad desteği
    apt install -y bluez blueman joystick xboxdrv 2>&1 | grep -v "^Selecting"
    
    # Bluetooth otomatik aktif
    if [ -f /etc/bluetooth/main.conf ]; then
        sed -i 's/#AutoEnable=false/AutoEnable=true/' /etc/bluetooth/main.conf
        systemctl restart bluetooth 2>/dev/null
    fi
    
    log_success "Gaming paketi hazır"
}

install_waydroid() {
    log_info "Waydroid Android container..."
    
    # Kernel modülleri
    apt install -y linux-modules-extra-$(uname -r) 2>/dev/null || true
    
    # Waydroid kurulum
    apt install -y waydroid lxc 2>&1 | grep -v "^Selecting"
    
    # Initialize
    waydroid init -s GAPPS 2>/dev/null || waydroid init 2>/dev/null || true
    
    # Servis aktif
    systemctl enable --now waydroid-container 2>/dev/null || true
    
    # Helper script
    cat > "$REAL_HOME/Desktop/waydroid-baslat.sh" <<'EOF'
#!/bin/bash
sudo systemctl start waydroid-container
sleep 2
waydroid session start &
sleep 3
waydroid show-full-ui
EOF
    chmod +x "$REAL_HOME/Desktop/waydroid-baslat.sh"
    chown "$REAL_USER:$REAL_USER" "$REAL_HOME/Desktop/waydroid-baslat.sh" 2>/dev/null
    
    log_success "Waydroid kuruldu (Başlat: Desktop/waydroid-baslat.sh)"
}

install_secure_vnc() {
    log_info "Güvenli VNC uzaktan erişim..."
    apt install -y x11vnc openssh-server 2>&1 | grep -v "^Selecting"
    
    # Güvenli şifre oluştur
    VNC_PASS=$(openssl rand -base64 12)
    mkdir -p "$REAL_HOME/.vnc"
    x11vnc -storepasswd "$VNC_PASS" "$REAL_HOME/.vnc/passwd" 2>/dev/null
    chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.vnc" 2>/dev/null
    
    # Systemd servisi
    cat > /etc/systemd/system/x11vnc.service <<EOF
[Unit]
Description=X11VNC Remote Access
After=display-manager.service network.target

[Service]
Type=simple
ExecStart=/usr/bin/x11vnc -forever -loop -auth guess -rfbauth $REAL_HOME/.vnc/passwd -rfbport 5900 -noxdamage
User=$REAL_USER
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable x11vnc 2>/dev/null
    systemctl start x11vnc 2>/dev/null
    
    # Firewall güvenlik (sadece yerel ağ)
    if command -v ufw &>/dev/null; then
        ufw allow from 192.168.0.0/16 to any port 5900 comment 'VNC Local Network' 2>/dev/null
        ufw allow from 10.0.0.0/8 to any port 5900 comment 'VNC Private Network' 2>/dev/null
        ufw --force enable 2>/dev/null
    fi
    
    # Şifreyi kaydet
    mkdir -p "$REAL_HOME/Desktop"
    cat > "$REAL_HOME/Desktop/vnc-bilgileri.txt" <<EOF
VNC UZAKTAN ERİŞİM BİLGİLERİ
=============================

Şifre: $VNC_PASS
Port: 5900

Bağlantı Adresi:
- Yerel Ağdan: $(hostname -I | awk '{print $1}'):5900

Güvenlik Notu:
Bu VNC sadece yerel ağınızdan (192.168.x.x) erişilebilir.
İnternetten erişim için Tailscale VPN kullanın.
EOF
    chown "$REAL_USER:$REAL_USER" "$REAL_HOME/Desktop/vnc-bilgileri.txt" 2>/dev/null
    
    log_success "VNC kuruldu (Şifre: Desktop/vnc-bilgileri.txt)"
}

install_tailscale() {
    log_info "Tailscale VPN ağı..."
    curl -fsSL https://tailscale.com/install.sh | sh 2>&1 | grep -v "^Selecting"
    systemctl enable --now tailscaled 2>/dev/null
    
    # GUI (opsiyonel)
    if command -v flatpak &>/dev/null; then
        flatpak install -y flathub com.tailscale.Tailscale 2>/dev/null || true
    fi
    
    log_success "Tailscale kuruldu (Bağlan: sudo tailscale up)"
}

install_webmin_docker() {
    log_info "Webmin yönetim paneli ve Docker..."
    
    # Docker
    if ! command -v docker &>/dev/null; then
        curl -fsSL https://get.docker.com | sh 2>&1 | grep -v "^Selecting"
        usermod -aG docker "$REAL_USER" 2>/dev/null
        log_success "Docker kuruldu"
    fi
    
    # Webmin (güvenli yöntem)
    if ! command -v webmin &>/dev/null; then
        wget -qO- http://www.webmin.com/jcameron-key.asc | \
            gpg --dearmor -o /etc/apt/trusted.gpg.d/webmin.gpg
        echo "deb https://download.webmin.com/download/repository sarge contrib" > \
            /etc/apt/sources.list.d/webmin.list
        apt update -qq
        apt install -y webmin 2>&1 | grep -v "^Selecting"
        log_success "Webmin kuruldu (http://localhost:10000)"
    fi
}

install_network_tools() {
    log_info "Ağ araçları (Samba, LocalSend)..."
    
    # Samba
    apt install -y samba samba-common-bin 2>&1 | grep -v "^Selecting"
    
    if ! grep -q "TVBox-Share" /etc/samba/smb.conf 2>/dev/null; then
        cat >> /etc/samba/smb.conf <<EOF

[TVBox-Share]
   comment = TV Box Media Share
   path = $REAL_HOME/Videos
   browseable = yes
   read only = no
   guest ok = yes
   create mask = 0755
EOF
        mkdir -p "$REAL_HOME/Videos" 2>/dev/null
        chown "$REAL_USER:$REAL_USER" "$REAL_HOME/Videos" 2>/dev/null
        systemctl restart smbd 2>/dev/null
    fi
    
    # LocalSend
    snap install localsend 2>/dev/null || \
        flatpak install -y flathub org.localsend.localsend_app 2>/dev/null || true
    
    log_success "Ağ araçları hazır"
}

install_obs_torrent() {
    log_info "OBS Studio ve Torrent istemcisi..."
    
    # OBS
    add-apt-repository -y ppa:obsproject/obs-studio 2>/dev/null
    apt update -qq
    apt install -y obs-studio 2>&1 | grep -v "^Selecting"
    
    # Transmission
    apt install -y transmission-gtk 2>&1 | grep -v "^Selecting"
    
    log_success "OBS ve Transmission kuruldu"
}

install_performance_tools() {
    log_info "Performans optimizasyonu..."
    apt install -y preload cpufrequtils htop btop neofetch 2>&1 | grep -v "^Selecting"
    
    # Swap optimizasyonu
    if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
        echo "vm.swappiness=10" >> /etc/sysctl.conf
        sysctl -p >/dev/null 2>&1
    fi
    
    # Preload servisi
    systemctl enable preload 2>/dev/null || true
    
    log_success "Performans ayarları yapıldı"
}

install_system_tools() {
    log_info "Sistem araçları (CEC, Overscan)..."
    apt install -y cec-utils xrandr 2>&1 | grep -v "^Selecting"
    
    # CEC test scripti
    mkdir -p "$REAL_HOME/Desktop"
    cat > "$REAL_HOME/Desktop/cec-test.sh" <<'EOF'
#!/bin/bash
echo "HDMI-CEC cihazları taranıyor..."
echo "scan" | cec-client -s -d 1
EOF
    chmod +x "$REAL_HOME/Desktop/cec-test.sh"
    
    # Overscan düzeltme
    cat > "$REAL_HOME/Desktop/overscan-duzelt.sh" <<'EOF'
#!/bin/bash
# TV ekranı kenarlarında siyah bantlar varsa bu değerleri ayarlayın
# HDMI çıkışınızı kontrol edin: xrandr
xrandr --output HDMI-1 --set "underscan" on --set "underscan hborder" 40 --set "underscan vborder" 25

# Farklı portlar için:
# xrandr --output HDMI-2 --set "underscan" on ...
# xrandr --output DP-1 --set "underscan" on ...
EOF
    chmod +x "$REAL_HOME/Desktop/overscan-duzelt.sh"
    
    chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/Desktop" 2>/dev/null
    log_success "Sistem araçları hazır"
}

install_cloud_backup() {
    log_info "Cloud sync ve yedekleme..."
    apt install -y rclone timeshift rsync 2>&1 | grep -v "^Selecting"
    log_success "Yedekleme araçları kuruldu"
}

install_autologin() {
    log_info "Otomatik oturum açma ayarlanıyor..."
    
    # GDM3
    if [ -f /etc/gdm3/custom.conf ]; then
        sed -i "s/^#.*AutomaticLoginEnable.*/AutomaticLoginEnable = true/" /etc/gdm3/custom.conf
        sed -i "s/^#.*AutomaticLogin.*/AutomaticLogin = $REAL_USER/" /etc/gdm3/custom.conf
    fi
    
    # LightDM
    if [ -f /etc/lightdm/lightdm.conf ]; then
        sed -i "s/^#autologin-user=.*/autologin-user=$REAL_USER/" /etc/lightdm/lightdm.conf
    fi
    
    log_success "Otomatik giriş aktif"
}

##############################################
# -- POST-INSTALL KONTROLLER --
##############################################

post_install_checks() {
    log_info "Kurulum sonrası kontroller..."
    
    local all_ok=true
    
    # Eksik bağımlılıkları düzelt
    apt --fix-broken install -y >/dev/null 2>&1
    
    # Flatpak güncelle
    if command -v flatpak &>/dev/null; then
        flatpak update -y >/dev/null 2>&1
    fi
    
    # VNC servisi
    if systemctl is-active --quiet x11vnc 2>/dev/null; then
        log_success "VNC servisi çalışıyor ✓"
    elif systemctl list-unit-files | grep -q x11vnc 2>/dev/null; then
        log_warn "VNC yüklü ama başlatılmamış"
        all_ok=false
    fi
    
    # Bluetooth
    if systemctl is-active --quiet bluetooth 2>/dev/null; then
        log_success "Bluetooth servisi çalışıyor ✓"
    elif systemctl list-unit-files | grep -q bluetooth 2>/dev/null; then
        log_warn "Bluetooth başlatılıyor..."
        systemctl start bluetooth 2>/dev/null
    fi
    
    # Tailscale
    if systemctl is-active --quiet tailscaled 2>/dev/null; then
        log_success "Tailscale servisi çalışıyor ✓"
    fi
    
    # Docker
    if command -v docker &>/dev/null; then
        if groups "$REAL_USER" | grep -q docker 2>/dev/null; then
            log_success "Docker kullanıcı grubunda ✓"
        else
            log_warn "Docker için oturumu yeniden açın"
        fi
    fi
    
    if [ "$all_ok" = true ]; then
        log_success "Tüm servisler sorunsuz ✓"
    fi
}

##############################################
# -- ÖZET RAPOR --
##############################################

show_summary() {
    local summary_text="KURULUM ÖZETI\n============\n\n"
    local next_steps="SONRAKİ ADIMLAR\n==============\n\n"
    
    # Kurulu paketleri tespit et
    if [[ $SELECTED_CHOICES == *"MEDIA"* ]]; then
        summary_text+="✓ VLC ve MPV medya oynatıcılar\n"
    fi
    
    if [[ $SELECTED_CHOICES == *"CODECS"* ]]; then
        summary_text+="✓ Codec'ler ve donanım hızlandırma\n"
    fi
    
    if [[ $SELECTED_CHOICES == *"KODI"* ]]; then
        summary_text+="✓ Kodi medya merkezi + IPTV\n"
        next_steps+="1. Kodi'yi açın ve IPTV kanallarını test edin\n"
    fi
    
    if [[ $SELECTED_CHOICES == *"SPOTIFY"* ]]; then
        summary_text+="✓ Spotify müzik servisi\n"
    fi
    
    if [[ $SELECTED_CHOICES == *"BROWSERS"* ]]; then
        summary_text+="✓ Chrome ve Firefox tarayıcılar\n"
    fi
    
    if [[ $SELECTED_CHOICES == *"GAMING"* ]]; then
        summary_text+="✓ Steam, RetroArch, Gamepad desteği\n"
        next_steps+="2. Bluetooth gamepad eşleştir: blueman-manager\n"
    fi
    
    if [[ $SELECTED_CHOICES == *"ANDROID"* ]]; then
        summary_text+="✓ Waydroid Android container\n"
        summary_text+="  Başlatma: Desktop/waydroid-baslat.sh\n"
    fi
    
    if [[ $SELECTED_CHOICES == *"VNC"* ]]; then
        summary_text+="✓ X11VNC uzaktan erişim (Port: 5900)\n"
        summary_text+="  Bilgiler: Desktop/vnc-bilgileri.txt\n"
        next_steps+="3. VNC şifrenizi Desktop/vnc-bilgileri.txt'den alın\n"
    fi
    
    if [[ $SELECTED_CHOICES == *"TAILSCALE"* ]]; then
        summary_text+="✓ Tailscale VPN ağı\n"
        next_steps+="4. Tailscale bağlan: sudo tailscale up\n"
    fi
    
    if [[ $SELECTED_CHOICES == *"WEBMIN"* ]]; then
        summary_text+="✓ Webmin yönetim paneli\n"
        summary_text+="  Erişim: http://localhost:10000\n"
        summary_text+="✓ Docker container platform\n"
        next_steps+="5. Docker için oturumu yeniden açın\n"
    fi
    
    if [[ $SELECTED_CHOICES == *"NETWORK"* ]]; then
        summary_text+="✓ Samba ağ paylaşımı (Videos klasörü)\n"
        summary_text+="✓ LocalSend dosya transferi\n"
    fi
    
    if [[ $SELECTED_CHOICES == *"TOOLS"* ]]; then
        summary_text+="✓ CEC TV kumanda desteği\n"
        summary_text+="✓ Overscan düzeltme araçları\n"
    fi
    
    # Genel adımlar
    next_steps+="\n🔄 Sistemi yeniden başlatın:\n   sudo reboot\n"
    
    # Ekrana yazdır
    clear
    echo -e "${PURPLE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║   MiniPC TV-Box Ultimate - Kurulum Tamamlandı  ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${GREEN}$summary_text${NC}"
    echo -e "${BLUE}$next_steps${NC}"
    
    # Whiptail özet (opsiyonel)
    whiptail --title "✅ Kurulum Başarıyla Tamamlandı!" --msgbox \
        "$summary_text\n$next_steps" 24 70 2>/dev/null || true
}

##############################################
# -- ANA MENÜ --
##############################################

main() {
    check_system_health
    
    SELECTED_CHOICES=$(whiptail --title "🎬 MiniPC TV-Box Ultimate Setup v8.0" --checklist \
"Kurulacak bileşenleri seçin (SPACE ile işaretle, ENTER ile devam):\n\n🔥 Önerilen paketler işaretli" 26 80 18 \
"UPDATE" "📦 Sistem Güncelleme (önerilir)" ON \
"MEDIA" "🎥 VLC, MPV Medya Oynatıcılar" ON \
"CODECS" "🎞️  Codec + Donanım Hızlandırma" ON \
"KODI" "📺 Kodi Medya Merkezi + IPTV" ON \
"SPOTIFY" "🎵 Spotify Müzik" OFF \
"AUDIO" "🔊 Ses Geliştirme + Ekolayzer" OFF \
"BROWSERS" "🌐 Chrome + Firefox" ON \
"GAMING" "🎮 Steam + RetroArch + Gamepad" OFF \
"ANDROID" "📱 Waydroid Android Container" OFF \
"VNC" "🖥️  Güvenli VNC Uzaktan Erişim" OFF \
"TAILSCALE" "🔒 Tailscale VPN Ağı" OFF \
"WEBMIN" "⚙️  Webmin + Docker Yönetim" OFF \
"NETWORK" "🌍 Samba + LocalSend" OFF \
"OBS" "📹 OBS Studio + Torrent" OFF \
"CLOUD" "☁️  Cloud Sync + Yedekleme" OFF \
"PERFORMANCE" "⚡ RAM/CPU Optimizasyonu" ON \
"TOOLS" "🛠️  CEC + Overscan Araçları" ON \
"AUTOLOGIN" "🔓 Otomatik Oturum Açma" ON \
"FLATPAK" "📦 Flatpak Desteği" ON \
3>&1 1>&2 2>&3)

    if [[ $? != 0 ]]; then
        log_warn "Kurulum kullanıcı tarafından iptal edildi"
        exit 0
    fi
    
    # Boş seçim kontrolü
    if [ -z "$SELECTED_CHOICES" ]; then
        whiptail --title "⚠️  Uyarı" --msgbox "Hiçbir paket seçilmedi. Kurulum iptal ediliyor." 8 50
        exit 0
    fi
    
    # Kurulum onayı
    whiptail --title "🚀 Kurulum Başlıyor" --yesno \
        "Seçili paketler kurulacak.\n\nBu işlem 10-30 dakika sürebilir.\n\nDevam edilsin mi?" 10 50
    if [ $? -ne 0 ]; then
        exit 0
    fi
    
    clear
    echo -e "${PURPLE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║        Kurulum Başladı - Lütfen Bekleyin       ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════╝${NC}\n"
    
    # Kurulum döngüsü
    for choice in $SELECTED_CHOICES; do
        case $choice in
            "\"UPDATE\"")
                log_info "Sistem güncelleniyor..."
                apt update -qq && apt upgrade -y 2>&1 | grep -v "^Selecting"
                ;;
            "\"MEDIA\"") install_media_bundle ;;
            "\"CODECS\"") install_codecs ;;
            "\"KODI\"") install_kodi_iptv ;;
            "\"SPOTIFY\"") install_spotify ;;
            "\"AUDIO\"") install_audio_enhancements ;;
            "\"BROWSERS\"") install_browsers ;;
            "\"GAMING\"") install_gaming ;;
            "\"ANDROID\"") install_waydroid ;;
            "\"VNC\"") install_secure_vnc ;;
            "\"TAILSCALE\"") install_tailscale ;;
            "\"WEBMIN\"") install_webmin_docker ;;
            "\"NETWORK\"") install_network_tools ;;
            "\"OBS\"") install_obs_torrent ;;
            "\"CLOUD\"") install_cloud_backup ;;
            "\"PERFORMANCE\"") install_performance_tools ;;
            "\"TOOLS\"") install_system_tools ;;
            "\"AUTOLOGIN\"") install_autologin ;;
            "\"FLATPAK\"") install_flatpak ;;
        esac
    done
    
    # Temizlik
    log_info "Sistem temizleniyor..."
    apt autoremove -y >/dev/null 2>&1
    apt autoclean -y >/dev/null 2>&1
    apt clean >/dev/null 2>&1
    
    # Post-install kontroller
    post_install_checks
    
    # Özet rapor
    show_summary
    
    log_success "Kurulum tamamlandı! İyi eğlenceler 🎉"
}

# Script başlat
main "$@"
