# Backend Bağlantı Kurulumu

Backend başka bir bilgisayarda çalışıyorsa, Flutter uygulamasını backend'e bağlamak için aşağıdaki adımları izleyin:

## 1️⃣ Backend Bilgisayarının IP Adresini Öğrenin

### macOS/Linux:
Terminal'de şu komutu çalıştırın:
```bash
ifconfig | grep "inet "
```
veya
```bash
ipconfig getifaddr en0
```

### Windows:
Command Prompt'ta şu komutu çalıştırın:
```bash
ipconfig
```
`IPv4 Address` satırındaki adresi bulun (örn: 192.168.1.100)

## 2️⃣ Flutter Config Dosyasını Güncelleyin

`lib/core/config/api_config.dart` dosyasını açın ve `baseUrl` değerini bulduğunuz IP adresi ile değiştirin:

```dart
static const String baseUrl = 'http://192.168.1.100:8080'; // IP adresinizi buraya yazın
```

## 3️⃣ Önemli Kontroller

### ✅ Aynı WiFi Ağında Olmalı
- Flutter uygulamasının çalıştığı cihaz/simulator
- Backend'in çalıştığı bilgisayar
- İkisi de **aynı WiFi ağında** olmalı!

### ✅ Backend Port'u Kontrol Edin
- Backend'iniz hangi port'ta çalışıyor? (genelde 8080)
- Firewall'ın bu portu engellemediğinden emin olun

### ✅ Backend Çalışıyor mu?
Backend bilgisayarında test edin:
```bash
curl http://localhost:8080/api/auth/me
```
veya tarayıcıda:
```
http://localhost:8080/api/auth/me
```

## 4️⃣ Test Senaryoları

### iOS Simulator:
- Mac'inizde çalışıyorsa: `http://localhost:8080` kullanabilirsiniz
- Başka bilgisayardaysa: `http://<IP-ADRESI>:8080` kullanın

### Android Emulator:
- Backend aynı bilgisayardaysa: `http://10.0.2.2:8080` kullanın
- Başka bilgisayardaysa: `http://<IP-ADRESI>:8080` kullanın

### Fiziksel Cihaz (iPhone/Android):
- **Mutlaka** `http://<IP-ADRESI>:8080` formatını kullanın
- localhost çalışmaz!

## 5️⃣ Sorun Giderme

### "Connection refused" hatası:
- Backend'in çalıştığından emin olun
- IP adresini doğru yazdığınızdan emin olun
- Port numarasını kontrol edin

### "Network error" hatası:
- Her iki cihaz aynı WiFi'de mi kontrol edin
- Firewall ayarlarını kontrol edin
- Backend bilgisayarında port'un açık olduğundan emin olun

### iOS Simulator'da çalışmıyor:
- Mac'inizde backend çalışıyorsa `localhost` kullanabilirsiniz
- Başka bilgisayardaysa IP adresi kullanın

