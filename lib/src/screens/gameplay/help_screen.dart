import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/atlas_aware_image.dart';

/// Help screen data loaded from JSON
class HelpScreenData {
  final int schemaVersion;
  final String screen;
  final String title;
  final String frameImage;
  final UIConfig ui;
  final List<HelpSection> sections;

  HelpScreenData({
    required this.schemaVersion,
    required this.screen,
    required this.title,
    required this.frameImage,
    required this.ui,
    required this.sections,
  });

  factory HelpScreenData.fromJson(Map<String, dynamic> json) {
    return HelpScreenData(
      schemaVersion: json['schemaVersion'],
      screen: json['screen'],
      title: json['title'],
      frameImage: json['frameImage'],
      ui: UIConfig.fromJson(json['ui']),
      sections: (json['sections'] as List)
          .map((e) => HelpSection.fromJson(e))
          .toList(),
    );
  }
}

/// UI configuration
class UIConfig {
  final double panelWidthFactor;
  final double panelMaxWidth;
  final double panelHeightFactor;
  final FrameInsetsConfig frameInsets;
  final ContentBoxConfig contentBox;
  final ButtonConfig button;

  UIConfig({
    required this.panelWidthFactor,
    required this.panelMaxWidth,
    required this.panelHeightFactor,
    required this.frameInsets,
    required this.contentBox,
    required this.button,
  });

  factory UIConfig.fromJson(Map<String, dynamic> json) {
    return UIConfig(
      panelWidthFactor: json['panelWidthFactor'].toDouble(),
      panelMaxWidth: json['panelMaxWidth'].toDouble(),
      panelHeightFactor: json['panelHeightFactor'].toDouble(),
      frameInsets: FrameInsetsConfig.fromJson(json['frameInsets']),
      contentBox: ContentBoxConfig.fromJson(json['contentBox']),
      button: ButtonConfig.fromJson(json['button']),
    );
  }
}

/// Frame insets configuration - defines the safe area inside the scroll frame
class FrameInsetsConfig {
  final double leftFactor;
  final double rightFactor;
  final double topFactor;
  final double bottomFactor;
  final double minLeft;
  final double minRight;
  final double minTop;
  final double minBottom;

  FrameInsetsConfig({
    required this.leftFactor,
    required this.rightFactor,
    required this.topFactor,
    required this.bottomFactor,
    required this.minLeft,
    required this.minRight,
    required this.minTop,
    required this.minBottom,
  });

  factory FrameInsetsConfig.fromJson(Map<String, dynamic> json) {
    return FrameInsetsConfig(
      leftFactor: (json['leftFactor'] as num).toDouble(),
      rightFactor: (json['rightFactor'] as num).toDouble(),
      topFactor: (json['topFactor'] as num).toDouble(),
      bottomFactor: (json['bottomFactor'] as num).toDouble(),
      minLeft: (json['minLeft'] as num).toDouble(),
      minRight: (json['minRight'] as num).toDouble(),
      minTop: (json['minTop'] as num).toDouble(),
      minBottom: (json['minBottom'] as num).toDouble(),
    );
  }
}

/// Content box configuration
class ContentBoxConfig {
  final Color backgroundColor;
  final double backgroundOpacity;
  final Color borderColor;
  final double borderWidth;
  final double borderRadius;
  final double padding;
  final double scrollRightPadding;
  final ScrollbarConfig scrollbar;

  ContentBoxConfig({
    required this.backgroundColor,
    required this.backgroundOpacity,
    required this.borderColor,
    required this.borderWidth,
    required this.borderRadius,
    required this.padding,
    required this.scrollRightPadding,
    required this.scrollbar,
  });

  factory ContentBoxConfig.fromJson(Map<String, dynamic> json) {
    return ContentBoxConfig(
      backgroundColor: _hexToColor(json['backgroundColorHex']),
      backgroundOpacity: json['backgroundOpacity'].toDouble(),
      borderColor: _hexToColor(json['borderColorHex']),
      borderWidth: json['borderWidth'].toDouble(),
      borderRadius: json['borderRadius'].toDouble(),
      padding: json['padding'].toDouble(),
      scrollRightPadding: json['scrollRightPadding'].toDouble(),
      scrollbar: ScrollbarConfig.fromJson(json['scrollbar']),
    );
  }
}

/// Scrollbar configuration
class ScrollbarConfig {
  final bool thumbVisibility;
  final double thickness;
  final double radius;

  ScrollbarConfig({
    required this.thumbVisibility,
    required this.thickness,
    required this.radius,
  });

  factory ScrollbarConfig.fromJson(Map<String, dynamic> json) {
    return ScrollbarConfig(
      thumbVisibility: json['thumbVisibility'],
      thickness: json['thickness'].toDouble(),
      radius: json['radius'].toDouble(),
    );
  }
}

/// Button configuration
class ButtonConfig {
  final String text;
  final double widthFactor;
  final Map<String, double> heightClamp;
  final Color backgroundColor;
  final double radius;
  final double elevation;

  ButtonConfig({
    required this.text,
    required this.widthFactor,
    required this.heightClamp,
    required this.backgroundColor,
    required this.radius,
    required this.elevation,
  });

  factory ButtonConfig.fromJson(Map<String, dynamic> json) {
    return ButtonConfig(
      text: json['text'],
      widthFactor: json['widthFactor'].toDouble(),
      heightClamp: {
        'min': json['heightClamp']['min'].toDouble(),
        'max': json['heightClamp']['max'].toDouble(),
      },
      backgroundColor: _hexToColor(json['backgroundColorHex']),
      radius: json['radius'].toDouble(),
      elevation: json['elevation'].toDouble(),
    );
  }
}

/// Help section with header and blocks
class HelpSection {
  final String header;
  final List<ContentBlock> blocks;

  HelpSection({
    required this.header,
    required this.blocks,
  });

  factory HelpSection.fromJson(Map<String, dynamic> json) {
    return HelpSection(
      header: json['header'],
      blocks: (json['blocks'] as List)
          .map((e) => ContentBlock.fromJson(e))
          .toList(),
    );
  }
}

/// Content block (text, bullets, or rows)
class ContentBlock {
  final String type;
  final String? text;
  final List<String>? bulletItems;
  final double? spriteSize;
  final double? spriteTextGap;
  final double? rowGap;
  final List<RowItem>? rowItems;

  ContentBlock({
    required this.type,
    this.text,
    this.bulletItems,
    this.spriteSize,
    this.spriteTextGap,
    this.rowGap,
    this.rowItems,
  });

  factory ContentBlock.fromJson(Map<String, dynamic> json) {
    return ContentBlock(
      type: json['type'],
      text: json['text'],
      bulletItems: json['items'] != null && json['type'] == 'bullets'
          ? List<String>.from(json['items'])
          : null,
      spriteSize: json['spriteSize']?.toDouble(),
      spriteTextGap: json['spriteTextGap']?.toDouble(),
      rowGap: json['rowGap']?.toDouble(),
      rowItems: json['items'] != null && json['type'] == 'rows'
          ? (json['items'] as List).map((e) => RowItem.fromJson(e)).toList()
          : null,
    );
  }
}

/// Row item with sprite, label, and text
class RowItem {
  final String sprite;
  final String label;
  final String text;

  RowItem({
    required this.sprite,
    required this.label,
    required this.text,
  });

  factory RowItem.fromJson(Map<String, dynamic> json) {
    return RowItem(
      sprite: json['sprite'],
      label: json['label'],
      text: json['text'],
    );
  }
}

/// Helper function to convert hex color to Color
Color _hexToColor(String hex) {
  final buffer = StringBuffer();
  if (hex.length == 7) buffer.write('ff');
  buffer.write(hex.replaceFirst('#', ''));
  return Color(int.parse(buffer.toString(), radix: 16));
}

/// Help screen widget - shows game instructions and tips
/// Content and styling loaded from JSON
class HelpScreen extends StatefulWidget {
  final VoidCallback onClose;

  const HelpScreen({
    super.key,
    required this.onClose,
  });

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  late ScrollController _scrollController;
  HelpScreenData? _helpData;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _loadHelpData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHelpData() async {
    try {
      // Load help screen based on language preference
      final prefs = await SharedPreferences.getInstance();
      final language = prefs.getString('language') ?? 'vi';
      
      final jsonString = await rootBundle.loadString('assets/json_design/help_screen_$language.json');
      final jsonData = json.decode(jsonString);
      setState(() {
        _helpData = HelpScreenData.fromJson(jsonData);
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load help data: $e';
      });
      debugPrint('[HelpScreen] Error loading JSON: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Material(
        color: Colors.black54,
        child: Center(
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    if (_helpData == null) {
      return const Material(
        color: Colors.black54,
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final screenSize = MediaQuery.of(context).size;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Dimmed background
          Positioned.fill(
            child: GestureDetector(
              onTap: widget.onClose,
              child: Container(
                color: Colors.black.withValues(alpha: 0.7),
              ),
            ),
          ),

          // Help panel - centered with SafeArea
          Center(
            child: SafeArea(
              child: _buildHelpPanel(context, screenSize),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpPanel(BuildContext context, Size screenSize) {
    final ui = _helpData!.ui;
    
    // Calculate panel size with max width constraint
    final calculatedWidth = screenSize.width * ui.panelWidthFactor;
    final panelWidth = calculatedWidth > ui.panelMaxWidth ? ui.panelMaxWidth : calculatedWidth;
    final panelHeight = screenSize.height * ui.panelHeightFactor;
    
    // Calculate frame insets (safe area inside the scroll artwork)
    final insets = ui.frameInsets;
    final left = (panelWidth * insets.leftFactor).clamp(insets.minLeft, double.infinity);
    final right = (panelWidth * insets.rightFactor).clamp(insets.minRight, double.infinity);
    final top = (panelHeight * insets.topFactor).clamp(insets.minTop, double.infinity);
    final bottom = (panelHeight * insets.bottomFactor).clamp(insets.minBottom, double.infinity);
    
    // Clamp font sizes for better responsiveness
    final titleFontSize = (panelWidth * 0.07).clamp(22.0, 40.0);
    final headerFontSize = (panelWidth * 0.045).clamp(15.0, 22.0);
    final textFontSize = (panelWidth * 0.038).clamp(13.0, 17.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // Prevent tap-through to background
      child: Container(
        width: panelWidth,
        height: panelHeight,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(_helpData!.frameImage),
            fit: BoxFit.fill,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(left, top, right, bottom),
          child: Column(
            children: [
              // Title
              Text(
                _helpData!.title,
                style: TextStyle(
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.brown.shade900,
                ),
              ),
              SizedBox(height: (panelHeight * 0.015).clamp(8.0, 16.0)),

              // Scrollable content with visible box and scrollbar
              Flexible(
                fit: FlexFit.tight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(ui.contentBox.borderRadius),
                  child: Container(
                    decoration: BoxDecoration(
                      color: ui.contentBox.backgroundColor.withValues(alpha: ui.contentBox.backgroundOpacity),
                      border: Border.all(
                        color: ui.contentBox.borderColor,
                        width: ui.contentBox.borderWidth,
                      ),
                      borderRadius: BorderRadius.circular(ui.contentBox.borderRadius),
                    ),
                    padding: EdgeInsets.all(ui.contentBox.padding),
                    child: Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: ui.contentBox.scrollbar.thumbVisibility,
                      thickness: ui.contentBox.scrollbar.thickness,
                      radius: Radius.circular(ui.contentBox.scrollbar.radius),
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: EdgeInsets.only(right: ui.contentBox.scrollRightPadding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _buildSections(headerFontSize, textFontSize),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              SizedBox(height: (panelHeight * 0.012).clamp(6.0, 12.0)),

              // Close button
              SizedBox(
                width: (panelWidth * ui.button.widthFactor).clamp(200.0, 400.0),
                height: (panelWidth * 0.10).clamp(ui.button.heightClamp['min']!, ui.button.heightClamp['max']!),
                child: ElevatedButton(
                  onPressed: widget.onClose,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ui.button.backgroundColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ui.button.radius),
                    ),
                    elevation: ui.button.elevation,
                  ),
                  child: Text(
                    ui.button.text,
                    style: TextStyle(
                      fontSize: (panelWidth * 0.04).clamp(15.0, 22.0),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSections(double headerFontSize, double textFontSize) {
    final List<Widget> widgets = [];
    
    for (int i = 0; i < _helpData!.sections.length; i++) {
      final section = _helpData!.sections[i];
      
      // Add section header
      widgets.add(
        Text(
          section.header,
          style: TextStyle(
            fontSize: headerFontSize,
            fontWeight: FontWeight.bold,
            color: Colors.brown.shade800,
          ),
        ),
      );
      widgets.add(const SizedBox(height: 10));
      
      // Add blocks
      for (final block in section.blocks) {
        widgets.add(_buildBlock(block, textFontSize));
        widgets.add(const SizedBox(height: 10));
      }
      
      // Add spacing between sections (except after last one)
      if (i < _helpData!.sections.length - 1) {
        widgets.add(const SizedBox(height: 12));
      }
    }
    
    return widgets;
  }

  Widget _buildBlock(ContentBlock block, double textFontSize) {
    switch (block.type) {
      case 'text':
        return Text(
          block.text!,
          style: TextStyle(
            fontSize: textFontSize,
            color: Colors.brown.shade700,
            height: 1.5,
          ),
        );
      
      case 'bullets':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: block.bulletItems!.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6.0, left: 8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• ',
                    style: TextStyle(
                      fontSize: textFontSize,
                      color: Colors.brown.shade700,
                      height: 1.5,
                    ),
                  ),
                  Flexible(
                    fit: FlexFit.tight,
                    child: Text(
                      item,
                      style: TextStyle(
                        fontSize: textFontSize,
                        color: Colors.brown.shade700,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      
      case 'rows':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: block.rowItems!.asMap().entries.map((entry) {
            final item = entry.value;
            final isLast = entry.key == block.rowItems!.length - 1;
            
            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : block.rowGap!),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: block.spriteSize,
                    height: block.spriteSize,
                    child: AtlasAwareImage(
                      assetPath: item.sprite,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: block.spriteSize,
                          height: block.spriteSize,
                          color: Colors.grey.shade300,
                          child: const Icon(Icons.image_not_supported, size: 20),
                        );
                      },
                    ),
                  ),
                  SizedBox(width: block.spriteTextGap),
                  Flexible(
                    fit: FlexFit.tight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: textFontSize,
                            fontWeight: FontWeight.bold,
                            color: Colors.brown.shade800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.text,
                          style: TextStyle(
                            fontSize: textFontSize * 0.95,
                            color: Colors.brown.shade700,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      
      default:
        return const SizedBox.shrink();
    }
  }
}
