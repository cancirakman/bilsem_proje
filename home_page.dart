import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart'; 
import 'package:flutter/services.dart'; 
import 'package:geolocator/geolocator.dart'; // Konum için
import 'tflite_classifier.dart'; 
import 'database_manager.dart'; // Realtime DB ve Storage için

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  File? image;
  final picker = ImagePicker();
  bool _isPicking = false; 
  
  // TFLite ve Database Sınıflarını tanımlıyoruz
  late TFLiteClassifier _classifier;
  final DatabaseManager _dbManager = DatabaseManager(); // Database Manager örneği
  
  // Sınıflandırma sonucunu tutmak için
  String _classificationResult = "Başlamak için fotoğraf çekin veya seçin."; 

  @override
  void initState() {
    super.initState();
    _classifier = TFLiteClassifier();
    _classifier.loadModel();
  }

  @override
  void dispose() {
    _classifier.close();
    super.dispose();
  }

  // Konum izinlerini kontrol eder ve mevcut konumu alır
  Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Konum servislerinin açık olup olmadığını kontrol et
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Konum servisleri kapalı. Lütfen açın.')));
      }
      return null;
    }

    // İzin durumunu kontrol et
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return null;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Konum izinleri kalıcı olarak reddedildi.')),
          );
      }
      return null;
    }

    // Konumu al
    return await Geolocator.getCurrentPosition(
    // Platforma özel ayarları kullanıyoruz
    locationSettings: AndroidSettings(
      accuracy: LocationAccuracy.high, // Yüksek hassasiyet istiyoruz
      forceLocationManager: true, // Bazı cihazlarda daha iyi çalışır
      intervalDuration: const Duration(seconds: 4), // Opsiyonel
      distanceFilter: 100, // Opsiyonel: 100 metreden az değişirse güncelleme
    ),
  );
  }


  // Veriyi Realtime DB ve Storage'a kaydetme işlevi
  Future<void> _saveData({
    required File imageFile,
    required String birdName,
    required double confidence,
  }) async {
    // 1. Konumu al
    Position? currentPosition = await _getCurrentLocation();
    
    if (currentPosition == null) {
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kayıt başarısız: Konum alınamadı.')),
          );
          // Konum alınamazsa sonucu güncelle
          setState(() {
              _classificationResult += "\n(Konum Kaydedilemedi, Kayıt İptal Edildi)";
          });
        }
        return;
    }

    try {
      // 2. Fotoğrafı Storage'a yükle
      String imageUrl = await _dbManager.uploadImageAndGetUrl(imageFile);

      // 3. Verileri Realtime Database'e kaydet
      await _dbManager.saveObservation(
        birdName: birdName,
        confidence: confidence,
        latitude: currentPosition.latitude,
        longitude: currentPosition.longitude,
        imageUrl: imageUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kayıt Database\'e başarıyla eklendi! 💾')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Veri kaydında kritik hata: ${e.toString()}')),
        );
      }
    }
  }


  // Galeriye Kaydetme İşlevi (Aynı kaldı)
  Future<void> saveImageToGallery(XFile pickedFile) async {
    final bytes = await pickedFile.readAsBytes();
    final result = await ImageGallerySaverPlus.saveImage(
      Uint8List.fromList(bytes),
      quality: 80, 
      name: "TFLite_Photo_${DateTime.now().millisecondsSinceEpoch}", 
    );
    
    if (!mounted) return; 

    if (result != null && result['isSuccess']) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fotoğraf başarıyla Galeriye kaydedildi!')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaydetme başarısız oldu.')),
      );
    }
  }

  // Fotoğraf Çekme/Seçme ve Sınıflandırma İşlevi
  Future<void> pickImage(ImageSource source) async {
    if (_isPicking) return; 
    
    // İşlem başladığında durumu güncelle
    setState(() {
      _isPicking = true;
      _classificationResult = "Sınıflandırma yapılıyor...";
    });

    try {
      final pickedFile = await picker.pickImage(source: source);

      if (pickedFile != null) {
        
        setState(() {
          image = File(pickedFile.path);
        });

        if (source == ImageSource.camera) {
          await saveImageToGallery(pickedFile);
        }
        
        // TFLite Sınıflandırmasını Başlat
        final results = await _classifier.classifyImage(pickedFile.path);

        if (mounted) {
            setState(() {
                if (results != null && results.isNotEmpty) {
                    final bestResult = results.first; 
                    _classificationResult = 
                        "${bestResult['label']} (${(bestResult['confidence'] * 100).toStringAsFixed(2)}%)";
                    
                    // KRİTİK ADIM: Sınıflandırma bitti, veriyi kaydet.
                    _saveData(
                      imageFile: File(pickedFile.path),
                      birdName: bestResult['label'],
                      confidence: bestResult['confidence'],
                    );

                } else {
                    _classificationResult = "Model sonucu alınamadı.";
                }
            });
        }
      } else {
         // Fotoğraf seçimi iptal edilirse
         if (mounted) {
             setState(() {
                _classificationResult = "Seçim iptal edildi.";
             });
         }
      }

    } catch (e) {
      if (mounted) {
        setState(() {
           _classificationResult = "Hata oluştu: ${e.toString()}";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İşlem sırasında hata oluştu: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
          child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center, 
                children: [
                  const Text("Sınıflandırma Sonucu:", 
                    style: TextStyle(color: Colors.white70, fontSize: 16)),
                  
                  // Sınıflandırma Sonucunu Gösteren Alan
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _classificationResult,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  SizedBox(
                      height: 300,
                      width: 300,
                      child: image != null
                          ? Image.file(image!)
                          : Center(
                              child: Text(
                                _isPicking ? "Lütfen bekleyin..." : "No image selected",
                                style: const TextStyle(color: Colors.white70),
                              ),
                            )),
                  const SizedBox(height: 20),
                  
                  if (_isPicking) 
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(color: Colors.white),
                    ) 
                  else 
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: () => pickImage(ImageSource.camera),
                          child: const Text("Camera"),
                        ),
                        ElevatedButton(
                          onPressed: () => pickImage(ImageSource.gallery),
                          child: const Text("Gallery"),
                        )
                      ],
                    ),
                ],
              ),
            ),
      ),
      backgroundColor: const Color.fromARGB(255, 16, 157, 192),
    );
  }
}