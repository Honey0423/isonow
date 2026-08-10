import 'package:flutter/material.dart';
import 'iso_detail_screen.dart';

class ProjectScreen extends StatelessWidget {
  final String projectName;

  const ProjectScreen({
    super.key,
    required this.projectName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(projectName),
      ),

      body: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Text(
              'ISO 도면 목록',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 30),


            Card(
              child: ListTile(
                title: const Text(
                  'OD25-POW-E-0038-01'
                ),
                subtitle: const Text(
                  'Revision 03'
                ),
                trailing: const Icon(
                  Icons.picture_as_pdf
                ),

                onTap: () {

                  Navigator.push(
                  context,
                    MaterialPageRoute(
                      builder: (context)=> ISODetailScreen(
                      isoName:'OD25-POW-E-0038-01',
                      ),
                    ),
                  );

                },


              ),
            ),


            Card(
              child: ListTile(
                title: const Text(
                  'OD25-POW-E-0039-01'
                ),
                subtitle: const Text(
                  'Revision 00'
                ),
                trailing: const Icon(
                  Icons.picture_as_pdf
                ),

                onTap: () {

                },
              ),
            ),

          ],
        ),
      ),
    );
  }
}