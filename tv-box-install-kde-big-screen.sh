#!/usr/bin/env bash

# =================================================================
# KDE BIGSCREEN TV LAUNCHER - UBUNTU KURULUM
# 
# Ubuntu GNOME'u bozmadan KDE Bigscreen ekler
# TV için optimize edilmiş Android TV benzeri arayüz
# =================================================================

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[ℹ️]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[⚠️]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# Root kontrolü
if [[ $EUID -ne 0 ]]; then
    echo "Bu script sudo ile çalıştırılmalı:"
    echo "sudo bash $0"
    exit 1
fi

REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6)

clear
echo -e "${PURPLE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║                                                ║${NC}"
echo -e "${PURPLE}║       📺 KDE BIGSCREEN TV LAUNCHER 📺          ║${NC}"
echo -e "${PURPLE}║                                                ║${NC}"
echo -e "${PURPLE}║   Android TV benzeri arayüz Ubuntu'da!        ║${NC}"
echo -e "${PURPLE}║                                                ║${NC}"
echo -e "${PURPLE}╚════════════════════════════════════════════════╝${NC}\n"

echo -e "${YELLOW}Bu script:${NC}"
echo "  • KDE Plasma ve Bigscreen'i kurar"
echo "  • GNOME'unuzu bozmaz (oturum seçiminde ikisi de olur)"
echo "  • TV uygulamalarını ekler (Kodi, Chrome, Steam vb.)"
echo "  • Uzaktan kumanda desteği kurar"
echo "  • Otomatik başlatma ayarlar (isteğe bağlı)"
echo ""

read -p "Devam etmek istiyor musunuz? (e/h): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ee]$ ]]; then
    log_warn "Kurulum iptal edildi"
    exit 0
fi

##############################################
# STEP 1: KDE PLASMA KURULUMU
##############################################

step1_install_kde() {
    log_info "ADIM 1/6: KDE Plasma Desktop kuruluyor..."
    
    # KDE minimal kurulum (GNOME'u bozmaz)
    apt update -qq
    
    log_info "KDE Plasma paketi indiriliyor (bu biraz sürebilir)..."
    apt install -y kde-plasma-desktop plasma-nm plasma-pa 2>&1 | grep -E "Unpacking|Setting up" || true
    
    # Ses ve ağ yönetimi
    apt install -y pulseaudio-module-bluetooth bluez-tools
    
    log_success "KDE Plasma kuruldu"
    log_info "Not: Giriş ekranında 'Plasma' seçeneği göreceksiniz"
}

##############################################
# STEP 2: KDE BIGSCREEN KURULUMU
##############################################

step2_install_bigscreen() {
    log_info "ADIM 2/6: KDE Bigscreen TV arayüzü kuruluyor..."
    
    # Bigscreen PPA'sı
    add-apt-repository -y ppa:plasma-bigscreen/release 2>/dev/null || {
        log_warn "PPA eklenemedi, manuel ekleniyor..."
        echo "deb http://ppa.launchpad.net/plasma-bigscreen/release/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/bigscreen.list
        apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 2C65B94F 2>/dev/null
    }
    
    apt update -qq
    apt install -y plasma-bigscreen 2>&1 | grep -E "Unpacking|Setting up" || true
    
    # Bigscreen bileşenleri
    apt install -y plasma-remotecontrollers qml-module-qtmultimedia
    
    log_success "KDE Bigscreen kuruldu"
}

##############################################
# STEP 3: TV UYGULAMALARI
##############################################

step3_install_apps() {
    log_info "ADIM 3/6: TV uygulamaları kuruluyor..."
    
    # Kodi
    log_info "📺 Kodi..."
    apt install -y kodi kodi-inputstream-adaptive kodi-pvr-iptvsimple 2>&1 | grep -v "Selecting"
    
    # Chrome
    log_info "🌐 Chrome..."
    if [ ! -f /usr/bin/google-chrome ]; then
        wget -qO /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
        apt install -y /tmp/chrome.deb 2>&1 | grep -v "Selecting"
        rm -f /tmp/chrome.deb
    fi
    
    # VLC
    log_info "🎥 VLC..."
    apt install -y vlc 2>&1 | grep -v "Selecting"
    
    # Spotify (isteğe bağlı)
    read -p "Spotify kurulsun mu? (e/h): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ee]$ ]]; then
        log_info "🎵 Spotify..."
        curl -sS https://download.spotify.com/debian/pubkey_7A3A762FAFD4A51F.gpg | \
            gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg
        echo "deb http://repository.spotify.com stable non-free" > /etc/apt/sources.list.d/spotify.list
        apt update -qq
        apt install -y spotify-client 2>&1 | grep -v "Selecting"
    fi
    
    log_success "TV uygulamaları kuruldu"
}

##############################################
# STEP 4: UZAKTAN KUMANDA DESTEĞİ
##############################################

step4_remote_control() {
    log_info "ADIM 4/6: Uzaktan kumanda desteği..."
    
    # HDMI-CEC
    apt install -y cec-utils
    
    # Bluetooth
    apt install -y bluez blueman
    systemctl enable bluetooth
    systemctl start bluetooth
    
    # Test scripti
    cat > "$REAL_HOME/Desktop/cec-test.sh" <<'EOF'
#!/bin/bash
echo "HDMI-CEC cihazları taranıyor..."
echo "scan" | cec-client -s -d 1
EOF
    chmod +x "$REAL_HOME/Desktop/cec-test.sh"
    chown "$REAL_USER:$REAL_USER" "$REAL_HOME/Desktop/cec-test.sh" 2>/dev/null
    
    log_success "Uzaktan kumanda hazır"
    log_info "Test için: ~/Desktop/cec-test.sh"
}

##############################################
# STEP 5: BIGSCREEN YAPILANDIRMA
##############################################

step5_configure_bigscreen() {
    log_info "ADIM 5/6: Bigscreen ayarları yapılandırılıyor..."
    
    # Kullanıcı ayar dizini
    mkdir -p "$REAL_HOME/.config"
    
    # Bigscreen otomatik başlatma ayarı
    cat > "$REAL_HOME/.config/startbigscreen.sh" <<'EOF'
#!/bin/bash
# KDE Bigscreen TV Mode
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
/usr/bin/plasmashell -p org.kde.plasma.bigscreen
EOF
    chmod +x "$REAL_HOME/.config/startbigscreen.sh"
    chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config" 2>/dev/null
    
    log_success "Bigscreen yapılandırıldı"
}

##############################################
# STEP 6: OTURUM AYARLARI
##############################################

step6_session_setup() {
    log_info "ADIM 6/6: Oturum ayarları..."
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}OTURUM SEÇİMİ${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Şimdi 3 seçeneğiniz var:"
    echo ""
    echo -e "${GREEN}1) GNOME (Mevcut)${NC}"
    echo "   Normal Ubuntu masaüstü"
    echo "   İşinizi görmek için"
    echo ""
    echo -e "${BLUE}2) Plasma (KDE Normal)${NC}"
    echo "   KDE masaüstü deneyimi"
    echo "   Daha gelişmiş ayarlar"
    echo ""
    echo -e "${PURPLE}3) Plasma Bigscreen (TV Modu)${NC}"
    echo "   TV için optimize arayüz"
    echo "   Uzaktan kumanda ile kullanım"
    echo ""
    echo "Giriş ekranında (GDM3) hangisini varsayılan yapmak istersiniz?"
    echo ""
    echo "a) GNOME'da kal (değişiklik yok)"
    echo "b) Plasma Bigscreen yap (TV modu)"
    echo "c) Her açılışta sorulan bırak"
    echo ""
    
    read -p "Seçiminiz (a/b/c): " -n 1 -r
    echo
    
    case $REPLY in
        [Bb])
            log_info "Bigscreen varsayılan oturum yapılıyor..."
            
            # SDDM kurulumu (KDE için daha iyi)
            apt install -y sddm sddm-theme-breeze
            
            # SDDM'i varsayılan yap
            systemctl disable gdm3 2>/dev/null
            systemctl enable sddm
            
            # Bigscreen otomatik giriş
            mkdir -p /etc/sddm.conf.d
            cat > /etc/sddm.conf.d/autologin.conf <<EOF
[Autologin]
User=$REAL_USER
Session=plasma-bigscreen
EOF
            
            log_success "Bigscreen varsayılan yapıldı"
            log_warn "Yeniden başlatınca direkt TV modunda açılacak!"
            ;;
        [Cc])
            log_info "Manuel seçim aktif kalacak"
            ;;
        *)
            log_info "GNOME varsayılan kalacak (değişiklik yok)"
            ;;
    esac
}

##############################################
# POST-INSTALL KONTROL
##############################################

post_install_check() {
    log_info "Kurulum kontrol ediliyor..."
    
    local has_error=0
    
    # KDE kuruldu mu?
    if ! dpkg -l | grep -q plasma-desktop; then
        log_error "KDE Plasma kurulmamış!"
        has_error=1
    else
        log_success "KDE Plasma ✓"
    fi
    
    # Bigscreen kuruldu mu?
    if ! dpkg -l | grep -q plasma-bigscreen; then
        log_error "Bigscreen kurulmamış!"
        has_error=1
    else
        log_success "KDE Bigscreen ✓"
    fi
    
    # Kodi kuruldu mu?
    if command -v kodi &>/dev/null; then
        log_success "Kodi ✓"
    fi
    
    # Chrome kuruldu mu?
    if command -v google-chrome &>/dev/null; then
        log_success "Chrome ✓"
    fi
    
    # CEC çalışıyor mu?
    if command -v cec-client &>/dev/null; then
        log_success "HDMI-CEC ✓"
    fi
    
    if [ $has_error -eq 0 ]; then
        log_success "Tüm bileşenler başarıyla kuruldu!"
    else
        log_warn "Bazı bileşenler eksik olabilir"
    fi
}

##############################################
# KULLANIM REHBERİ
##############################################

show_guide() {
    clear
    echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                ║${NC}"
    echo -e "${GREEN}║     ✅ KDE BIGSCREEN KURULUMU TAMAMLANDI!      ║${NC}"
    echo -e "${GREEN}║                                                ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${BLUE}📺 NASIL KULLANILIR?${NC}"
    echo ""
    echo "1. Sistemi yeniden başlatın:"
    echo -e "   ${YELLOW}sudo reboot${NC}"
    echo ""
    echo "2. Giriş ekranında seçenekler:"
    echo "   • Ubuntu (GNOME) - Normal masaüstü"
    echo "   • Plasma - KDE masaüstü"
    echo "   • Plasma Bigscreen - TV modu ⭐"
    echo ""
    echo "3. TV modunda gezinme:"
    echo "   • Ok tuşları → Uygulama seç"
    echo "   • Enter → Uygulama başlat"
    echo "   • ESC → Geri dön"
    echo ""
    
    echo -e "${PURPLE}🎮 UZAKTAN KUMANDA${NC}"
    echo ""
    echo "• HDMI-CEC: TV kumandanız çalışabilir"
    echo "  Test: ~/Desktop/cec-test.sh"
    echo ""
    echo "• Bluetooth: Ayarlar > Bluetooth'tan eşleştirin"
    echo ""
    
    echo -e "${YELLOW}⚙️ AYARLAR${NC}"
    echo ""
    echo "• Bigscreen'den çıkış: ALT+F2 → 'killall plasmashell'"
    echo "• Normal KDE'ye geç: Oturumu kapat → Plasma seç"
    echo "• GNOME'a dön: Oturumu kapat → Ubuntu seç"
    echo ""
    
    echo -e "${GREEN}🎉 İYİ SEYİRLER!${NC}"
    echo ""
}

##############################################
# ANA KURULUM
##############################################

main() {
    # İnternet kontrolü
    if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        log_error "İnternet bağlantısı yok!"
        exit 1
    fi
    
    # Disk alanı kontrolü
    FREE_SPACE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$FREE_SPACE" -lt 5 ]; then
        log_warn "Disk alanı düşük: ${FREE_SPACE}GB"
        read -p "Devam edilsin mi? (e/h): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ee]$ ]]; then
            exit 0
        fi
    fi
    
    # Kurulum adımları
    step1_install_kde
    step2_install_bigscreen
    step3_install_apps
    step4_remote_control
    step5_configure_bigscreen
    step6_session_setup
    
    # Kontrol
    post_install_check
    
    # Temizlik
    apt autoremove -y >/dev/null 2>&1
    apt clean >/dev/null 2>&1
    
    # Rehber
    show_guide
}

main "$@"
