import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';

/// Renders the card's barcode at maximum contrast for checkout scanning.
/// The symbology recorded during the scan is reused so a cashier scanner
/// reads the same bars the physical card carries.
class BarcodeView extends StatelessWidget {
  const BarcodeView({
    super.key,
    required this.data,
    this.barcodeFormat,
    this.width = 320,
    this.height = 100,
    this.showText = false,
  });

  final String data;
  final String? barcodeFormat;
  final double width;
  final double height;
  final bool showText;

  static Barcode _resolve(String? format) {
    switch (format) {
      case 'ean13':
        return Barcode.ean13();
      case 'ean8':
        return Barcode.ean8();
      case 'ean2':
      case 'ean5':
        return Barcode.ean2(); // closest supported add-on
      case 'upcA':
        return Barcode.upcA();
      case 'upcE':
        return Barcode.upcE();
      case 'code39':
        return Barcode.code39();
      case 'code93':
        return Barcode.code93();
      case 'itf':
        return Barcode.itf();
      case 'codabar':
        return Barcode.codabar();
      case 'qr':
        return Barcode.qrCode();
      case 'code128':
      default:
        return Barcode.code128();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: BarcodeWidget(
        barcode: _resolve(barcodeFormat),
        data: data,
        width: width,
        height: height,
        drawText: showText,
        backgroundColor: Colors.white,
      ),
    );
  }
}
