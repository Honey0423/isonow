import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:pdfx/pdfx.dart';

class PDFViewerScreen extends StatefulWidget {
  // assets 안의 PDF 경로 (앱에 포함된 도면)
  final String pdfPath;
  final String title;

  // 앱에서 업로드한 ISO처럼 메모리에서 여는 PDF.
  // 값이 있으면 pdfPath 대신 이것을 연다.
  final Future<Uint8List>? pdfBytes;

  const PDFViewerScreen({
    super.key,
    required this.pdfPath,
    required this.title,
    this.pdfBytes,
  });

  @override
  State<PDFViewerScreen> createState() => _PDFViewerScreenState();
}

class _PDFViewerScreenState extends State<PDFViewerScreen> {
  late PdfControllerPinch pdfController;

  PdfDocument? _document;

  int _currentPage = 1;
  int _pageCount = 0;

  // ============================================================
  // 줌
  // ============================================================

  double _scale = 1.0;

  static const double _minScale = 0.5;
  static const double _maxScale = 5.0;
  static const double _scaleStep = 0.25;

  // ============================================================
  // 회전
  // ============================================================

  int _rotation = 0;

  // ============================================================
  // 오른쪽 페이지 목록
  // ============================================================

  bool _showThumbnails = true;

  @override
  void initState() {
    super.initState();

    final documentFuture = widget.pdfBytes != null
        ? PdfDocument.openData(
            widget.pdfBytes!,
          )
        : PdfDocument.openAsset(
            widget.pdfPath,
          );

    pdfController = PdfControllerPinch(
      document: documentFuture,
      initialPage: 1,
    );

    _loadDocument(documentFuture);
  }

  // ============================================================
  // PDF 로딩
  // ============================================================

  Future<void> _loadDocument(
    Future<PdfDocument> documentFuture,
  ) async {
    try {
      final document = await documentFuture;

      if (!mounted) return;

      setState(() {
        _document = document;
        _pageCount = document.pagesCount;
      });
    } catch (e) {
      debugPrint('PDF 로딩 오류: $e');
    }
  }

  @override
  void dispose() {
    pdfController.dispose();
    super.dispose();
  }

  // ============================================================
  // 페이지 이동
  // ============================================================

  void _goToPage(int page) {
    if (page < 1 || page > _pageCount) {
      return;
    }

    pdfController.jumpToPage(page);

    setState(() {
      _currentPage = page;
    });

    _resetView();
  }

  void _previousPage() {
    if (_currentPage <= 1) return;

    _goToPage(_currentPage - 1);
  }

  void _nextPage() {
    if (_currentPage >= _pageCount) return;

    _goToPage(_currentPage + 1);
  }

  // ============================================================
  // 줌
  // ============================================================

  void _setScale(double scale) {
    final newScale = scale.clamp(
      _minScale,
      _maxScale,
    );

    setState(() {
      _scale = newScale;
    });
  }

  void _zoomIn() {
    _setScale(_scale + _scaleStep);
  }

  void _zoomOut() {
    _setScale(_scale - _scaleStep);
  }

  // ============================================================
  // 회전
  // ============================================================

  void _rotateClockwise() {
    setState(() {
      _rotation = (_rotation + 90) % 360;
    });
  }

  void _rotateCounterClockwise() {
    setState(() {
      _rotation = (_rotation - 90) % 360;

      if (_rotation < 0) {
        _rotation += 360;
      }
    });
  }

  // ============================================================
  // 전체 보기 초기화
  // ============================================================

  void _resetView() {
    setState(() {
      _scale = 1.0;
      _rotation = 0;
    });
  }

  // ============================================================
  // 마우스 휠 줌
  // ============================================================

  void _handlePointerSignal(
    PointerSignalEvent event,
  ) {
    if (event is! PointerScrollEvent) {
      return;
    }

    final delta = event.scrollDelta.dy;

    if (delta < 0) {
      _zoomIn();
    } else if (delta > 0) {
      _zoomOut();
    }
  }

  // ============================================================
  // 페이지 썸네일 이미지 렌더링
  // ============================================================

  Future<PdfPageImage?> _renderThumbnail(
    int pageNumber,
  ) async {
    if (_document == null) {
      return null;
    }

    PdfPage? page;

    try {
      page = await _document!.getPage(pageNumber);

      final double originalWidth = page.width;
      final double originalHeight = page.height;

      // 썸네일용 해상도
      const double thumbnailWidth = 220;

      final double ratio =
          thumbnailWidth / originalWidth;

      final double thumbnailHeight =
          originalHeight * ratio;

      final image = await page.render(
        width: thumbnailWidth,
        height: thumbnailHeight,
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );

      return image;
    } catch (e) {
      debugPrint(
        '썸네일 렌더링 오류 - page $pageNumber: $e',
      );

      return null;
    } finally {
      if (page != null) {
        try {
          await page.close();
        } catch (_) {}
      }
    }
  }

  // ============================================================
  // 썸네일
  // ============================================================

  Widget _buildThumbnail(
    int pageNumber,
  ) {
    final bool isSelected =
        pageNumber == _currentPage;

    if (_document == null) {
      return const SizedBox(
        height: 150,
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return InkWell(
      onTap: () {
        _goToPage(pageNumber);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 6,
        ),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? Theme.of(context)
                    .colorScheme
                    .primary
                : Colors.grey.shade300,
            width: isSelected ? 3 : 1,
          ),
          color: isSelected
              ? Theme.of(context)
                  .colorScheme
                  .primary
                  .withOpacity(0.08)
              : Colors.white,
        ),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 595.2 / 841.68,
              child: ClipRRect(
                borderRadius:
                    BorderRadius.circular(3),
                child: FutureBuilder<PdfPageImage?>(
                  future: _renderThumbnail(pageNumber),
                  builder: (
                    context,
                    snapshot,
                  ) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      );
                    }

                    if (snapshot.hasError ||
                        !snapshot.hasData ||
                        snapshot.data == null) {
                      return const Center(
                        child: Icon(
                          Icons.picture_as_pdf,
                          color: Colors.grey,
                          size: 30,
                        ),
                      );
                    }

                    return Image.memory(
                      snapshot.data!.bytes,
                      fit: BoxFit.contain,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '$pageNumber',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 오른쪽 페이지 목록
  // ============================================================

  Widget _buildThumbnailPanel() {
    return Container(
      width: 150,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(
          left: BorderSide(
            color: Colors.grey.shade300,
          ),
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey.shade300,
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.layers_outlined,
                  size: 18,
                ),
                const SizedBox(width: 7),
                const Text(
                  '페이지',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '$_currentPage / $_pageCount',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _pageCount == 0
                ? const Center(
                    child:
                        CircularProgressIndicator(),
                  )
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(
                      vertical: 6,
                    ),
                    itemCount: _pageCount,
                    itemBuilder: (
                      context,
                      index,
                    ) {
                      return _buildThumbnail(
                        index + 1,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PDF 본체
  // ============================================================

  Widget _buildPdfView() {
    return Transform.rotate(
      angle:
          _rotation * math.pi / 180,
      child: Transform.scale(
        scale: _scale,
        child: PdfViewPinch(
          controller: pdfController,

          // PdfViewPinch 자체 핀치 줌 범위
          minScale: 0.5,
          maxScale: 5.0,

          onPageChanged: (page) {
            if (!mounted) return;

            setState(() {
              _currentPage = page;
            });
          },
        ),
      ),
    );
  }

  // ============================================================
  // 메인 PDF 영역
  // ============================================================

  Widget _buildPdfViewer() {
    return Expanded(
      child: Listener(
        onPointerSignal:
            _handlePointerSignal,
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: Colors.grey.shade300,
                child: ClipRect(
                  child: Center(
                    child: _buildPdfView(),
                  ),
                ),
              ),
            ),

            // ==================================================
            // 하단 컨트롤
            // ==================================================

            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color:
                        Colors.black.withOpacity(0.70),
                    borderRadius:
                        BorderRadius.circular(35),
                  ),
                  child: Row(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      // 이전 페이지
                      IconButton(
                        tooltip: '이전 페이지',
                        icon: const Icon(
                          Icons.chevron_left,
                          color: Colors.white,
                        ),
                        onPressed:
                            _currentPage > 1
                                ? _previousPage
                                : null,
                      ),

                      // 페이지 번호
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(
                          horizontal: 8,
                        ),
                        child: Text(
                          '$_currentPage / $_pageCount',
                          style:
                              const TextStyle(
                            color: Colors.white,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ),

                      // 다음 페이지
                      IconButton(
                        tooltip: '다음 페이지',
                        icon: const Icon(
                          Icons.chevron_right,
                          color: Colors.white,
                        ),
                        onPressed:
                            _currentPage <
                                    _pageCount
                                ? _nextPage
                                : null,
                      ),

                      Container(
                        width: 1,
                        height: 25,
                        margin:
                            const EdgeInsets.symmetric(
                          horizontal: 6,
                        ),
                        color: Colors.white24,
                      ),

                      // 반시계
                      IconButton(
                        tooltip:
                            '반시계 방향 회전',
                        icon: const Icon(
                          Icons.rotate_left,
                          color: Colors.white,
                        ),
                        onPressed:
                            _rotateCounterClockwise,
                      ),

                      // 각도
                      Text(
                        '$_rotation°',
                        style:
                            const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      // 시계
                      IconButton(
                        tooltip:
                            '시계 방향 회전',
                        icon: const Icon(
                          Icons.rotate_right,
                          color: Colors.white,
                        ),
                        onPressed:
                            _rotateClockwise,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ==================================================
            // 회전 상태
            // ==================================================

            if (_rotation != 0)
              Positioned(
                top: 15,
                left: 15,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color:
                        Colors.black.withOpacity(0.65),
                    borderRadius:
                        BorderRadius.circular(20),
                  ),
                  child: Text(
                    '회전 $_rotation°',
                    style:
                        const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 화면
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          // ====================================================
          // 축소
          // ====================================================

          IconButton(
            tooltip: '축소',
            icon: const Icon(Icons.remove),
            onPressed:
                _scale > _minScale
                    ? _zoomOut
                    : null,
          ),

          // ====================================================
          // 배율
          // ====================================================

          SizedBox(
            width: 55,
            child: Center(
              child: Text(
                '${(_scale * 100).round()}%',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ),
          ),

          // ====================================================
          // 확대
          // ====================================================

          IconButton(
            tooltip: '확대',
            icon: const Icon(Icons.add),
            onPressed:
                _scale < _maxScale
                    ? _zoomIn
                    : null,
          ),

          // ====================================================
          // 원래 보기
          // ====================================================

          IconButton(
            tooltip: '원래 보기',
            icon: const Icon(
              Icons.fit_screen,
            ),
            onPressed: _resetView,
          ),

          const SizedBox(width: 5),

          // ====================================================
          // 페이지 목록
          // ====================================================

          IconButton(
            tooltip: '페이지 목록',
            icon: Icon(
              _showThumbnails
                  ? Icons.view_sidebar
                  : Icons.view_sidebar_outlined,
            ),
            onPressed: () {
              setState(() {
                _showThumbnails =
                    !_showThumbnails;
              });
            },
          ),

          const SizedBox(width: 8),
        ],
      ),

      // ========================================================
      // PDF + 썸네일
      // ========================================================

      body: Row(
        children: [
          _buildPdfViewer(),

          if (_showThumbnails)
            _buildThumbnailPanel(),
        ],
      ),
    );
  }
}