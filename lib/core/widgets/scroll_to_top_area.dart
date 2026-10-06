import 'package:flutter/material.dart';

class ScrollToTopArea extends StatefulWidget {
  const ScrollToTopArea({super.key, required this.builder});

  final Widget Function(ScrollController controller) builder;

  @override
  State<ScrollToTopArea> createState() => _ScrollToTopAreaState();
}

class _ScrollToTopAreaState extends State<ScrollToTopArea> {
  final _controller = ScrollController();
  bool _showButton = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateButton);
  }

  void _updateButton() {
    final show = _controller.hasClients && _controller.offset > 200;
    if (show != _showButton) {
      setState(() => _showButton = show);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(child: widget.builder(_controller)),
      if (_showButton)
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.small(
            heroTag: null,
            tooltip: 'Наверх',
            onPressed: () {
              if (_controller.hasClients) {
                _controller.animateTo(
                  0,
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                );
              }
            },
            child: const Icon(Icons.arrow_upward),
          ),
        ),
    ],
  );
}
