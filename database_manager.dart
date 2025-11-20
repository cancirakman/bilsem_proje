import 'package:firebase_database/firebase_database.dart'; // Realtime DB
import 'package:firebase_storage/firebase_storage.dart'; // Storage
import 'dart:io';

class DatabaseManager {
  // Realtime Database referansını alıyoruz
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // 1. Fotoğrafı Storage'a yükler ve URL'sini döndürür
  Future<String> uploadImageAndGetUrl(File imageFile) async {
    // Storage'da benzersiz bir dosya yolu oluşturur
    String fileName = 'birds/${DateTime.now().millisecondsSinceEpoch}.jpg';
    Reference ref = _storage.ref().child(fileName);
    
    // Dosyayı yükle
    UploadTask uploadTask = ref.putFile(imageFile);
    
    // Yükleme tamamlanana kadar bekle ve URL'yi al
    TaskSnapshot snapshot = await uploadTask;
    String downloadUrl = await snapshot.ref.getDownloadURL();
    return downloadUrl;
  }

  // 2. Kuş Gözlemi Kaydını Realtime Database'e kaydeder
  Future<void> saveObservation({
    required String birdName,
    required double confidence,
    required double latitude,
    required double longitude,
    required String imageUrl,
  }) async {
    try {
      // JSON formatında veri haritası oluşturulur
      Map<String, dynamic> observationData = {
        'birdName': birdName,
        'confidence': confidence,
        'latitude': latitude,
        'longitude': longitude,
        'imageUrl': imageUrl,
        'timestamp': ServerValue.timestamp, // RTDB için sunucu zaman damgası
      };

      // 'observations' ana düğümünün altına otomatik bir anahtar (push) ile kaydeder
      await _dbRef.child('observations').push().set(observationData);
      
    } catch (e) {
      rethrow;
    }
  }
}