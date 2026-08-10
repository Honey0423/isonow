import 'package:flutter/material.dart';
import 'pdf_viewer_screen.dart';

class ISODetailScreen extends StatelessWidget {

  final String isoName;

  const ISODetailScreen({
    super.key,
    required this.isoName,
  });


  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: Text(isoName),
      ),


      body: Padding(
        padding: const EdgeInsets.all(30),

        child: Column(

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [


            Text(
              'Revision History',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),


            const SizedBox(height: 30),



            revisionCard(
              context,
              'Rev.03',
              '2026-08-04',
              true,
            ),


            revisionCard(
              context,
              'Rev.02',
              '2026-07-20',
              false,
            ),


            revisionCard(
              context,
              'Rev.01',
              '2026-06-10',
              false,
            ),


            revisionCard(
              context,
              'Rev.00',
              '2026-05-01',
              false,
            ),


          ],
        ),
      ),
    );
  }



  Widget revisionCard(
      BuildContext context,
      String revision,
      String date,
      bool latest,
      ){

    return Card(

      child: ListTile(

        leading: Icon(
          Icons.picture_as_pdf,
          color: latest ? Colors.green : Colors.grey,
        ),


        title: Row(
          children: [

            Text(
              revision,
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),


            if(latest)
              Container(

                margin: EdgeInsets.only(left:10),

                padding: EdgeInsets.symmetric(
                  horizontal:8,
                  vertical:3,
                ),

                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(5),
                ),

                child: Text(
                  'LATEST',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize:12,
                  ),
                ),

              )

          ],
        ),


        subtitle: Text(
          '수정일 : $date',
        ),


        trailing: Icon(
          Icons.arrow_forward,
        ),


        onTap:(){

          String revNumber = revision.replaceAll('Rev.', '');

          String pdfPath =
            'assets/pdf/${isoName}_Rev$revNumber.pdf';


          Navigator.push(
            context,
            MaterialPageRoute(
              builder:(context)=> PDFViewerScreen(
                pdfPath: pdfPath,

                title:
                '$isoName $revision',
              ),
            ),
          );

        },




      ),
    );

  }

}