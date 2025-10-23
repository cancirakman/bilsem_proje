import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img; 
import 'package:flutter/services.dart' show rootBundle;
import 'dart:typed_data'; // Uint8List için

class TFLiteClassifier {
  Interpreter? _interpreter; 
  List<String> _labels = []; 

  // Model dosya adları (Sizin assets klasörünüze göre ayarlandı)
  static const String _modelPath = 'assets/model_unquant.tflite';
  static const String _labelPath = 'assets/labels.txt';

  // Model ve etiketleri yükler
  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(_modelPath);
      
      // Etiketleri yükle
      String labelContent = await rootBundle.loadString(_labelPath);
      _labels = labelContent.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      
    } catch (e) {
      // Hata durumunda model nesnesi null kalabilir
      _labels = ['HATA: Model veya Etiket yüklenemedi'];
    }
  }

  // Görüntüyü ön işler, modeli çalıştırır ve sonuçları döndürür
  Future<List<Map<String, dynamic>>?> classifyImage(String imagePath) async {
    if (_interpreter == null) return null;
    
    final file = File(imagePath);
    if (!file.existsSync()) return null;

    // 1. Görüntü Ön İşleme
    img.Image? originalImage = img.decodeImage(file.readAsBytesSync());
    if (originalImage == null) return null;
    
    // Modelin beklediği boyuta yeniden boyutlandır (224x224 varsayımı)
    final img.Image resizedImage = img.copyResize(originalImage, width: 224, height: 224);

    // Girdi tamponunu hazırla: [1, 224, 224, 3] boyutunda Float32
    var input = List.filled(1 * 224 * 224 * 3, 0.0).reshape([1, 224, 224, 3]);

    // Görüntü verilerini, TFLite'ın beklediği RGB sırasına göre bir Uint8List olarak al.
    final Uint8List bytes = resizedImage.getBytes(
      order: img.ChannelOrder.rgb,
      alpha: 255, 
    );

    int pixelIndex = 0; // Byte dizisindeki konumu tutar

    // Görüntü verisini tampona kopyala ve normalleştir (0-255 -> 0-1)
    for (var y = 0; y < 224; y++) {
      for (var x = 0; x < 224; x++) {
        
        // RGB verileri byte dizisi içinde sırayla depolanır
        final int r = bytes[pixelIndex++];
        final int g = bytes[pixelIndex++];
        final int b = bytes[pixelIndex++];

        // Float model için normalizasyon (0-255 -> 0.0-1.0)
        input[0][y][x][0] = r / 255.0;   // R
        input[0][y][x][1] = g / 255.0; // G
        input[0][y][x][2] = b / 255.0;  // B
      }
    }

    // 2. Çıktı tamponunu hazırla
    var outputShape = _interpreter!.getOutputTensor(0).shape;
    var output = List.filled(outputShape.reduce((a, b) => a * b), 0.0).reshape(outputShape);

    // 3. Modeli çalıştır
    _interpreter!.run(input, output);

    // 4. Sonuçları işle ve sırala
    var confidences = output[0] as List<double>; 
    var results = <Map<String, dynamic>>[];

    for (int i = 0; i < confidences.length; i++) {
        String label = (i < _labels.length && _labels[i].isNotEmpty) ? _labels[i] : 'Bilinmeyen Sınıf $i';
        
        results.add({
            'label': label,
            'confidence': confidences[i],
        });
    }

    results.sort((a, b) => b['confidence'].compareTo(a['confidence']));
        
    return results; 
  }

  // Belleği serbest bırakır
  void close() {
    _interpreter?.close(); 
  }
}