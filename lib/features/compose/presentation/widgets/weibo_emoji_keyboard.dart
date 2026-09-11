import 'package:flutter/material.dart';

/// Comprehensive Weibo Emoji/Emotions Keyboard
class WeiboEmojiKeyboard extends StatelessWidget {
  final Function(String phrase) onEmojiSelected;
  final VoidCallback onBackspace;

  const WeiboEmojiKeyboard({
    super.key,
    required this.onEmojiSelected,
    required this.onBackspace,
  });

  static const List<Map<String, dynamic>> categories = [
    {
      'title': '常用',
      'items': [
        {'phrase': '[微笑]', 'char': '😊'},
        {'phrase': '[嘻嘻]', 'char': '😁'},
        {'phrase': '[哈哈]', 'char': '😃'},
        {'phrase': '[可爱]', 'char': '🥰'},
        {'phrase': '[可怜]', 'char': '🥺'},
        {'phrase': '[挖鼻]', 'char': '👃'},
        {'phrase': '[吃惊]', 'char': '😲'},
        {'phrase': '[害羞]', 'char': '😳'},
        {'phrase': '[挤眼]', 'char': '😉'},
        {'phrase': '[闭嘴]', 'char': '🤐'},
        {'phrase': '[鄙视]', 'char': '😒'},
        {'phrase': '[爱你]', 'char': '😍'},
        {'phrase': '[泪]', 'char': '😭'},
        {'phrase': '[偷笑]', 'char': '🤭'},
        {'phrase': '[亲亲]', 'char': '😘'},
        {'phrase': '[太开心]', 'char': '😆'},
        {'phrase': '[白眼]', 'char': '🙄'},
        {'phrase': '[右哼哼]', 'char': '😏'},
        {'phrase': '[左哼哼]', 'char': '😤'},
        {'phrase': '[嘘]', 'char': '🤫'},
        {'phrase': '[衰]', 'char': '😩'},
        {'phrase': '[委屈]', 'char': '🥺'},
        {'phrase': '[吐]', 'char': '🤮'},
        {'phrase': '[哈欠]', 'char': '🥱'},
        {'phrase': '[抱抱]', 'char': '🤗'},
        {'phrase': '[怒]', 'char': '😡'},
        {'phrase': '[疑问]', 'char': '❓'},
        {'phrase': '[馋嘴]', 'char': '😋'},
        {'phrase': '[拜拜]', 'char': '👋'},
        {'phrase': '[思考]', 'char': '🤔'},
        {'phrase': '[汗]', 'char': '😓'},
        {'phrase': '[困]', 'char': '😪'},
        {'phrase': '[睡]', 'char': '😴'},
        {'phrase': '[钱]', 'char': '🤑'},
        {'phrase': '[失望]', 'char': '😞'},
        {'phrase': '[酷]', 'char': '😎'},
        {'phrase': '[色]', 'char': '🤤'},
        {'phrase': '[流鼻血]', 'char': '🤤'},
        {'phrase': '[哼]', 'char': '😠'},
        {'phrase': '[鼓掌]', 'char': '👏'},
        {'phrase': '[晕]', 'char': '😵'},
        {'phrase': '[悲伤]', 'char': '😢'},
        {'phrase': '[抓狂]', 'char': '🤯'},
        {'phrase': '[黑线]', 'char': '😑'},
        {'phrase': '[阴险]', 'char': '😈'},
      ]
    },
    {
      'title': '热门',
      'items': [
        {'phrase': '[doge]', 'char': '🐶'},
        {'phrase': '[二哈]', 'char': '🐕'},
        {'phrase': '[旺柴]', 'char': '🐕'},
        {'phrase': '[喵喵]', 'char': '🐱'},
        {'phrase': '[吃瓜]', 'char': '🍉'},
        {'phrase': '[打call]', 'char': '🎉'},
        {'phrase': '[并不简单]', 'char': '🧐'},
        {'phrase': '[允悲]', 'char': '😂'},
        {'phrase': '[笑cry]', 'char': '🤣'},
        {'phrase': '[笑哭]', 'char': '🤣'},
        {'phrase': '[捂脸]', 'char': '🤦'},
        {'phrase': '[打脸]', 'char': '🤦'},
        {'phrase': '[机智]', 'char': '💡'},
        {'phrase': '[跪了]', 'char': '🧎'},
        {'phrase': '[给力]', 'char': '💪'},
        {'phrase': '[威武]', 'char': '🦁'},
        {'phrase': '[互粉]', 'char': '🤝'},
        {'phrase': '[猪头]', 'char': '🐷'},
        {'phrase': '[熊猫]', 'char': '🐼'},
        {'phrase': '[兔子]', 'char': '🐰'},
        {'phrase': '[奥特曼]', 'char': '🦸'},
        {'phrase': '[酸]', 'char': '🍋'},
        {'phrase': '[裂开]', 'char': '💔'},
        {'phrase': '[辣眼睛]', 'char': '🙈'},
        {'phrase': '[苦涩]', 'char': '🥲'},
        {'phrase': '[叹气]', 'char': '😮‍💨'},
        {'phrase': '[摸头]', 'char': '💆'},
        {'phrase': '[摊手]', 'char': '🤷'},
      ]
    },
    {
      'title': '符号',
      'items': [
        {'phrase': '[赞]', 'char': '👍'},
        {'phrase': '[点赞]', 'char': '👍'},
        {'phrase': '[good]', 'char': '👌'},
        {'phrase': '[ok]', 'char': '🆗'},
        {'phrase': '[耶]', 'char': '✌️'},
        {'phrase': '[NO]', 'char': '🙅'},
        {'phrase': '[弱]', 'char': '👎'},
        {'phrase': '[拳头]', 'char': '👊'},
        {'phrase': '[心]', 'char': '❤️'},
        {'phrase': '[伤心]', 'char': '💔'},
        {'phrase': '[比心]', 'char': '🫰'},
        {'phrase': '[作揖]', 'char': '🙏'},
        {'phrase': '[礼物]', 'char': '🎁'},
        {'phrase': '[蛋糕]', 'char': '🎂'},
        {'phrase': '[鲜花]', 'char': '💐'},
        {'phrase': '[送花花]', 'char': '🌸'},
        {'phrase': '[太阳]', 'char': '☀️'},
        {'phrase': '[月亮]', 'char': '🌙'},
        {'phrase': '[话筒]', 'char': '🎤'},
        {'phrase': '[蜡烛]', 'char': '🕯️'},
        {'phrase': '[锦鲤]', 'char': '🎏'},
        {'phrase': '[庆祝]', 'char': '🥳'},
      ]
    }
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: categories.length,
      child: Container(
        height: 240,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
          ),
        ),
        child: Column(
          children: [
            // Tabs Row
            Container(
              height: 36,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              child: Row(
                children: [
                  Expanded(
                    child: TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      indicatorColor: colorScheme.primary,
                      labelColor: colorScheme.primary,
                      unselectedLabelColor: colorScheme.onSurfaceVariant,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 16),
                      tabs: categories.map((c) => Tab(text: c['title'] as String)).toList(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.backspace_outlined, size: 20),
                    tooltip: '删除',
                    onPressed: onBackspace,
                  ),
                ],
              ),
            ),
            // Emoji Grids
            Expanded(
              child: TabBarView(
                children: categories.map((cat) {
                  final items = cat['items'] as List<Map<String, String>>;
                  return GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                      childAspectRatio: 1.0,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => onEmojiSelected(item['phrase']!),
                        child: Center(
                          child: Text(
                            item['char']!,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      );
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
