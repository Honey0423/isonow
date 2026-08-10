import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';


class PDFViewerScreen extends StatefulWidget {

  final String pdfPath;
  final String title;


  const PDFViewerScreen({
    super.key,
    required this.pdfPath,
    required this.title,
  });


  @override
  State<PDFViewerScreen> createState() => _PDFViewerScreenState();

}



class _PDFViewerScreenState extends State<PDFViewerScreen> {


  late PdfControllerPinch pdfController;


  @override
  void initState() {
    super.initState();


    pdfController = PdfControllerPinch(
      document: PdfDocument.openAsset(
        widget.pdfPath,
      ),
    );

  }



  @override
  Widget build(BuildContext context) {


    return Scaffold(

      appBar: AppBar(
        title: Text(widget.title),
      ),


      body: PdfViewPinch(
        controller: pdfController,
      ),

    );

  }

}