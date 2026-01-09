#!/usr/bin/env bash

# =================================================================
# MiniPC -> Ubuntu TV Launcher Edition v9.0
#
# Özellikler:
# ✓ Ubuntu TV Tarzı Dock Launcher
# ✓ Büyük İkonlar ve Yazılar (TV'den Okunabilir)
# ✓ Uzaktan Kumanda Desteği
# ✓ Otomatik Uygulama Dock'a Ekleme
# ✓ Kodi, Chrome, Steam vb. Tek Tıkla Başlatma
# =================================================================

set -u

cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ] && [ $exit_code -ne 130 ]; then
        echo -e "\033[0;31m[HATA] Beklenmeyen hata!\033[0m" >&2
    fi
}
trap cleanup EXIT

sed -i 's/\r$//' "$0" 2>/dev/null

# ROOT YETKİSİ
if [[ $EUID -ne 0 ]]; then
    if command -v zenity &>/dev/null; then
        zenity --info --title="Yönetici İzni" --text="Bu kurulum sudo yetkisi gerektirir.\n\nTamam'a basınca parolanız istenecek." --width=400 2>/dev/null
    fi
    exec sudo "$0" "$@"
fi

# DEĞİŞKENLER
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6)

if [ -z "$REAL_HOME" ] || [ "$REAL_USER" = "root" ]; then
    REAL_HOME="/root"
fi

# RENKLER
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[ℹ️]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[⚠️]${NC} $1"; }

##############################################
# UBUNTU TV LAUNCHER KURULUMU
##############################################

setup_ubuntu_tv_launcher() {
    log_info "Ubuntu TV Launcher hazırlanıyor..."
    
    # GNOME için Dash to Dock veya Plank kuralım
    local launcher_choice=""
    
    if command -v gnome-shell &>/dev/null; then
        log_info "GNOME Shell için Dash to Dock uzantısı kuruluyor..."
        
        # Dash to Dock uzantısı
        apt install -y gnome-shell-extension-dash-to-dock gnome-tweaks
        
        # Kullanıcı için aktif et
        sudo -u "$REAL_USER" gnome-extensions enable dash-to-dock@micxgx.gmail.com 2>/dev/null || true
        
        # TV Optimizasyonu - Büyük ikonlar, alt dock
        sudo -u "$REAL_USER" dconf write /org/gnome/shell/extensions/dash-to-dock/dock-position "'BOTTOM'" 2>/dev/null
        sudo -u "$REAL_USER" dconf write /org/gnome/shell/extensions/dash-to-dock/dash-max-icon-size 96 2>/dev/null
        sudo -u "$REAL_USER" dconf write /org/gnome/shell/extensions/dash-to-dock/icon-size-fixed true 2>/dev/null
        sudo -u "$REAL_USER" dconf write /org/gnome/shell/extensions/dash-to-dock/show-apps-at-top true 2>/dev/null
        sudo -u "$REAL_USER" dconf write /org/gnome/shell/extensions/dash-to-dock/show-trash false 2>/dev/null
        sudo -u "$REAL_USER" dconf write /org/gnome/shell/extensions/dash-to-dock/transparency-mode "'FIXED'" 2>/dev/null
        sudo -u "$REAL_USER" dconf write /org/gnome/shell/extensions/dash-to-dock/background-opacity 0.8 2>/dev/null
        
        launcher_choice="dash-to-dock"
    else
        log_info "Evrensel launcher için Plank kuruluyor..."
        
        # Plank - Basit ve şık dock
        apt install -y plank
        
        # Otomatik başlatma
        mkdir -p "$REAL_HOME/.config/autostart"
        cat > "$REAL_HOME/.config/autostart/plank.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Plank
Exec=plank
Icon=plank
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
        
        # Plank temalarını kur
        mkdir -p "$REAL_HOME/.local/share/plank/themes"
        
        launcher_choice="plank"
    fi
    
    log_success "TV Launcher hazır: $launcher_choice"
}

##############################################
# TV UYGULAMALARI KURULUMU
##############################################

install_tv_apps() {
    log_info "TV uygulamaları kuruluyor..."
    
    # Temel güncellemeler
    apt update -qq
    apt install -y software-properties-common wget curl
    
    # 1. KODI - Ana Medya Merkezi
    log_info "📺 Kodi Medya Merkezi..."
    apt install -y kodi kodi-inputstream-adaptive kodi-pvr-iptvsimple
    
    # 2. CHROME - Web Tarayıcı
    log_info "🌐 Google Chrome..."
    wget -qO /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    apt install -y /tmp/chrome.deb 2>&1 | grep -v "Selecting"
    rm -f /tmp/chrome.deb
    
    # 3. VLC - Yedek Medya Player
    log_info "🎥 VLC Player..."
    apt install -y vlc
    
    # 4. SPOTIFY (İsteğe bağlı)
    log_info "🎵 Spotify..."
    curl -sS https://download.spotify.com/debian/pubkey_7A3A762FAFD4A51F.gpg | \
        gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg
    echo "deb http://repository.spotify.com stable non-free" > /etc/apt/sources.list.d/spotify.list
    apt update -qq
    apt install -y spotify-client 2>&1 | grep -v "Selecting"
    
    # 5. STEAM - Oyun Platformu
    log_info "🎮 Steam Gaming..."
    wget -qO /tmp/steam.deb https://cdn.akamai.steamstatic.com/client/installer/steam.deb
    apt install -y /tmp/steam.deb 2>&1 | grep -v "Selecting"
    rm -f /tmp/steam.deb
    
    # 6. RETROARCH - Emülatör
    log_info "👾 RetroArch Emülatör..."
    apt install -y retroarch
    
    # 7. STREMIO - Film/Dizi
    log_info "🍿 Stremio..."
    wget -qO /tmp/stremio.deb https://dl.strem.io/linux/v4.4.168/stremio_4.4.168-1_amd64.deb
    apt install -y /tmp/stremio.deb 2>&1 | grep -v "Selecting"
    rm -f /tmp/stremio.deb
    
    # 8. DOSYA YÖNETİCİSİ (Büyük ikonlu)
    log_info "📁 Dosya Yöneticisi..."
    apt install -y nautilus
    
    log_success "Tüm TV uygulamaları kuruldu"
}

##############################################
# DOCK'A UYGULAMA EKLEME
##############################################

add_apps_to_dock() {
    log_info "Uygulamalar dock'a ekleniyor..."
    
    # GNOME Dash to Dock için
    if command -v gnome-shell &>/dev/null; then
        FAVORITES=(
            "'kodi.desktop'"
            "'google-chrome.desktop'"
            "'vlc.desktop'"
            "'spotify.desktop'"
            "'steam.desktop'"
            "'org.gnome.Nautilus.desktop'"
            "'retroarch.desktop'"
            "'stremio.desktop'"
            "'org.gnome.Settings.desktop'"
        )
        
        FAVORITES_STRING="[$(IFS=,; echo "${FAVORITES[*]}")]"
        sudo -u "$REAL_USER" dconf write /org/gnome/shell/favorite-apps "$FAVORITES_STRING" 2>/dev/null
        
        log_success "GNOME Dock'a uygulamalar eklendi"
        
    # Plank için
    elif command -v plank &>/dev/null; then
        mkdir -p "$REAL_HOME/.config/plank/dock1/launchers"
        
        # Uygulama kısayollarını kopyala
        for app in kodi google-chrome vlc spotify steam nautilus retroarch stremio; do
            if [ -f "/usr/share/applications/${app}.desktop" ]; then
                cp "/usr/share/applications/${app}.desktop" "$REAL_HOME/.config/plank/dock1/launchers/" 2>/dev/null
            fi
        done
        
        chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/plank"
        log_success "Plank'a uygulamalar eklendi"
    fi
}

##############################################
# TV OPTİMİZASYONU
##############################################

optimize_for_tv() {
    log_info "TV için sistem optimizasyonu..."
    
    # 1. BÜYÜK YAZI TİPİ
    if command -v gsettings &>/dev/null; then
        sudo -u "$REAL_USER" gsettings set org.gnome.desktop.interface text-scaling-factor 1.5 2>/dev/null
        sudo -u "$REAL_USER" gsettings set org.gnome.desktop.interface cursor-size 48 2>/dev/null
        log_success "Yazı boyutu TV için büyütüldü"
    fi
    
    # 2. OTOMATIK GİRİŞ
    if [ -f /etc/gdm3/custom.conf ]; then
        sed -i "s/^#.*AutomaticLoginEnable.*/AutomaticLoginEnable = true/" /etc/gdm3/custom.conf
        sed -i "s/^#.*AutomaticLogin.*/AutomaticLogin = $REAL_USER/" /etc/gdm3/custom.conf
        log_success "Otomatik giriş aktif"
    fi
    
    # 3. EKRAN KORUYUCU KAPALI
    sudo -u "$REAL_USER" gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null
    sudo -u "$REAL_USER" gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null
    
    # 4. HDMI-CEC DESTEĞI
    apt install -y cec-utils
    
    # 5. CODEC VE DONANIM HIZLANDIRMA
    apt install -y ubuntu-restricted-extras libavcodec-extra ffmpeg
    apt install -y intel-media-va-driver i965-va-driver vainfo mesa-va-drivers
    
    # 6. BLUETOOTH GAMEPAD/KUMANDA
    apt install -y bluez blueman
    systemctl enable bluetooth
    
    # 7. PERFORMANS
    apt install -y preload
    echo "vm.swappiness=10" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
    
    log_success "TV optimizasyonları tamamlandı"
}

##############################################
# UZAKTAN KUMANDA AYARLARI
##############################################

setup_remote_control() {
    log_info "Uzaktan kumanda desteği yapılandırılıyor..."
    
    # HDMI-CEC için otomatik başlatma scripti
    cat > "$REAL_HOME/Desktop/tv-kumanda-test.sh" <<'EOF'
#!/bin/bash
echo "HDMI-CEC TV Kumanda Test Ediliyor..."
echo ""
echo "TV kumandanızla ok tuşlarına basın."
echo "Cihazlar:"
echo "scan" | cec-client -s -d 1
EOF
    chmod +x "$REAL_HOME/Desktop/tv-kumanda-test.sh"
    chown "$REAL_USER:$REAL_USER" "$REAL_HOME/Desktop/tv-kumanda-test.sh"
    
    # Klavye kısayolları - TV kumanda simulasyonu
    sudo -u "$REAL_USER" gsettings set org.gnome.settings-daemon.plugins.media-keys home "['<Super>h']" 2>/dev/null
    
    log_success "Kumanda ayarları hazır (Test: Desktop/tv-kumanda-test.sh)"
}

##############################################
# KODI YAPILANDIRMA
##############################################

configure_kodi() {
    log_info "Kodi TV ayarları yapılandırılıyor..."
    
    mkdir -p "$REAL_HOME/.kodi/userdata"
    
    # Performans ayarları
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
  <gui>
    <algorithmdirtyregions>3</algorithmdirtyregions>
  </gui>
</advancedsettings>
EOF
    
    # IPTV klasörü
    mkdir -p "$REAL_HOME/.kodi/iptv"
    wget -qO "$REAL_HOME/.kodi/iptv/channels.m3u" "https://iptv-org.github.io/iptv/countries/tr.m3u" 2>/dev/null || \
        echo "#EXTM3U" > "$REAL_HOME/.kodi/iptv/channels.m3u"
    
    chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.kodi"
    log_success "Kodi yapılandırıldı"
}

##############################################
# MASAÜSTÜ KISAYOLLARI
##############################################

create_desktop_shortcuts() {
    log_info "Masaüstü kısayolları oluşturuluyor..."
    
    mkdir -p "$REAL_HOME/Desktop"
    
    # TV Modu Başlatıcı
    cat > "$REAL_HOME/Desktop/TV-Modu.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=📺 TV Modunu Başlat
Comment=Kodi'yi tam ekran başlat
Exec=kodi --fullscreen
Icon=kodi
Terminal=false
Categories=AudioVideo;
EOF
    
    # Web TV
    cat > "$REAL_HOME/Desktop/Web-TV.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=🌐 Web TV
Comment=Chrome'u tam ekran başlat
Exec=google-chrome --start-fullscreen --app=https://www.youtube.com/tv
Icon=google-chrome
Terminal=false
Categories=Network;
EOF
    
    chmod +x "$REAL_HOME/Desktop"/*.desktop
    chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/Desktop"
    
    log_success "Masaüstü kısayolları oluşturuldu"
}

##############################################
# ANA KURULUM
##############################################

main() {
    clear
    echo -e "${PURPLE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║                                                ║${NC}"
    echo -e "${PURPLE}║      📺 Ubuntu TV Launcher Edition v9.0 📺      ║${NC}"
    echo -e "${PURPLE}║                                                ║${NC}"
    echo -e "${PURPLE}║   MiniPC'nizi Android TV gibi kullanın!        ║${NC}"
    echo -e "${PURPLE}║                                                ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════╝${NC}\n"
    
    log_info "Kurulum başlıyor..."
    sleep 2
    
    # Sistem kontrolü
    if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        log_warn "İnternet bağlantısı yok!"
        exit 1
    fi
    
    # Ana kurulum adımları
    install_tv_apps
    setup_ubuntu_tv_launcher
    add_apps_to_dock
    configure_kodi
    optimize_for_tv
    setup_remote_control
    create_desktop_shortcuts
    
    # Temizlik
    apt autoremove -y >/dev/null 2>&1
    apt clean >/dev/null 2>&1
    
    # Özet
    clear
    echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                ║${NC}"
    echo -e "${GREEN}║        ✅ UBUNTU TV KURULUMU TAMAMLANDI!        ║${NC}"
    echo -e "${GREEN}║                                                ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${BLUE}📺 DOCK'A EKLENDİ:${NC}"
    echo "   • Kodi (Medya Merkezi)"
    echo "   • Google Chrome (Web TV)"
    echo "   • VLC Player"
    echo "   • Spotify"
    echo "   • Steam"
    echo "   • RetroArch"
    echo "   • Stremio"
    echo ""
    
    echo -e "${YELLOW}🎮 MASAÜSTÜ KISAYOLLAR:${NC}"
    echo "   • TV Modunu Başlat (Kodi)"
    echo "   • Web TV (YouTube TV)"
    echo "   • TV Kumanda Test"
    echo ""
    
    echo -e "${PURPLE}⚙️ YAPILANSistemi yeniden başlatın:${NC}"
    echo "   1. Büyük yazı boyutu (TV için)"
    echo "   2. Otomatik giriş"
    echo "   3. Ekran koruyucu kapalı"
    echo "   4. HDMI-CEC kumanda desteği"
    echo "   5. Bluetooth gamepad hazır"
    echo ""
    
    echo -e "${RED}🔄 SONRAKİ ADIM:${NC}"
    echo "   sudo reboot"
    echo ""
    
    log_success "Ubuntu TV hazır! İyi seyirler 🍿"
}

main "$@"
