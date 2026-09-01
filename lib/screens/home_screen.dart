import 'package:flutter/material.dart';

import 'project_screen.dart';

class HomeScreen extends StatelessWidget {
  final String projectId;
  final String projectName;

  const HomeScreen({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(projectName),
      ),

      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [

          // ========================================
          // 프로젝트 이름
          // ========================================
          Text(
            projectName,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 25),

          // ========================================
          // 도면
          // ========================================
          _MenuCard(
            icon: Icons.architecture,
            title: '도면',
            description: 'ISO · P&ID · Plan DWG · ...',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProjectScreen(
                    projectName: projectName,
                  ),
                ),
              );
            },
          ),

          // ========================================
          // 안전
          // ========================================
          _MenuCard(
            icon: Icons.health_and_safety,
            title: '안전',
            description: '금일 안전 주요 사항',
            onTap: () {
              // TODO: 안전 화면
            },
          ),

          // ========================================
          // 품질
          // ========================================
          _MenuCard(
            icon: Icons.fact_check,
            title: '품질',
            description: 'Punch List',
            onTap: () {
              // TODO: 품질 화면
            },
          ),

          // ========================================
          // 자재
          // ========================================
          _MenuCard(
            icon: Icons.inventory_2,
            title: '자재',
            description: '자재 발주 및 현황',
            onTap: () {
              // TODO: 자재 화면
            },
          ),
        ],
      ),
    );
  }
}


// ==================================================
// 메뉴 카드
// ==================================================

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 15),
      elevation: 2,

      child: InkWell(
        onTap: onTap,

        borderRadius: BorderRadius.circular(12),

        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 22,
          ),

          child: Row(
            children: [

              // ====================================
              // 아이콘
              // ====================================
              Container(
                width: 52,
                height: 52,

                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius:
                      BorderRadius.circular(12),
                ),

                child: Icon(
                  icon,
                  size: 28,
                  color: Colors.grey.shade700,
                ),
              ),

              const SizedBox(width: 18),

              // ====================================
              // 제목 + 설명
              // ====================================
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [

                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),

              // ====================================
              // 화살표
              // ====================================
              Icon(
                Icons.chevron_right,
                color: Colors.grey.shade500,
              ),
            ],
          ),
        ),
      ),
    );
  }
}