import 'package:flutter/material.dart';
import 'project_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ISONow'),
      ),

      body: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            const Text(
              '프로젝트 선택',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 30),

            Card(
              child: ListTile(
                title: const Text('M15X Project'),
                subtitle: const Text('ISO 도면 관리'),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () {

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProjectScreen(
                        projectName: 'M15X Project',
                      ),
                    ),
                  );

                },



              ),
            ),

            Card(
              child: ListTile(
                title: const Text('M16X Project'),
                subtitle: const Text('ISO 도면 관리'),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () {

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProjectScreen(
                        projectName: 'M15X Project',
                      ),
                    ),
                  );
                  
                },
              ),
            ),

          ],
        ),
      ),
    );
  }
}