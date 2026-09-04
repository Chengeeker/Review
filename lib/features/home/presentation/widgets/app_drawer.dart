import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/auth/auth_provider.dart';
import '../../../../core/utils/haptic_feedback_util.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../auth/presentation/login_page.dart';
import '../../../drawer_features/presentation/browsing_history_page.dart';
import '../../../drawer_features/presentation/chaohua_center_page.dart';
import '../../../drawer_features/presentation/likes_favorites_page.dart';
import '../../../drawer_features/presentation/my_follows_page.dart';
import '../../../drawer_features/presentation/my_messages_page.dart';
import '../../../feed/presentation/group_management_page.dart';
import '../../../profile/presentation/user_profile_page.dart';

/// 微博主界面侧边栏 Drawer (精简纯净版：赞和评论、我的收藏、我的微博、我的分组、我的关注、超话中心、浏览记录)
class AppDrawer extends ConsumerStatefulWidget {
  const AppDrawer({super.key});

  @override
  ConsumerState<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends ConsumerState<AppDrawer> {
  @override
  void initState() {
    super.initState();
    // 打开侧边栏时自动静默刷新当前登录用户的最新 UID、昵称与头像
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = ref.read(authProvider);
      if (auth.isLoggedIn && (auth.uid == null || auth.nickname == '已登录用户' || auth.avatar == null)) {
        ref.read(authProvider.notifier).refreshUserProfile();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isLoggedIn = authState.isLoggedIn;
    final nickname = authState.nickname ?? (isLoggedIn ? '已登录用户' : '未登录 / 访客');
    final avatar = authState.avatar ?? '';

    return Drawer(
      width: 280,
      backgroundColor: isDark ? const Color(0xFF1B1B1E) : theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 顶部个人头像与昵称区
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 头像
                  GestureDetector(
                    onTap: () {
                      HapticFeedbackUtil.light();
                      Navigator.pop(context);
                      if (isLoggedIn && authState.uid != null) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (ctx) => UserProfilePage(
                              uid: authState.uid,
                              screenName: authState.nickname,
                            ),
                          ),
                        );
                      } else {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (ctx) => const LoginPage()),
                        );
                      }
                    },
                    child: AppAvatar(
                      url: avatar,
                      size: 64,
                      name: nickname,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 昵称（点击进入个人主页或登录页）
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      HapticFeedbackUtil.light();
                      Navigator.pop(context);
                      if (isLoggedIn && authState.uid != null) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (ctx) => UserProfilePage(
                              uid: authState.uid,
                              screenName: authState.nickname,
                            ),
                          ),
                        );
                      } else {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (ctx) => const LoginPage()),
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      child: Text(
                        nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, thickness: 0.5),

            // 2. 侧边栏功能列表 (精简纯净 7 大核心功能)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  // 1. 赞和收藏 (双顶栏：我的赞 / 我的收藏)
                  _buildDrawerItem(
                    context,
                    icon: Icons.favorite_rounded,
                    title: '赞和收藏',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (ctx) => const LikesFavoritesPage()),
                      );
                    },
                  ),


                  // 4. 我的分组
                  _buildDrawerItem(
                    context,
                    icon: Icons.group_rounded,
                    title: '我的分组',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (ctx) => const GroupManagementPage()),
                      );
                    },
                  ),

                  // 5. 我的关注 (双顶栏：关注的人 / 关注的超话)
                  _buildDrawerItem(
                    context,
                    icon: Icons.people_alt_rounded,
                    title: '我的关注',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (ctx) => const MyFollowsPage()),
                      );
                    },
                  ),

                  // 6. 我的消息 (聚合通知与私信会话)
                  _buildDrawerItem(
                    context,
                    icon: Icons.mail_outline_rounded,
                    title: '我的消息',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (ctx) => const MyMessagesPage()),
                      );
                    },
                  ),

                  // 7. 超话中心 (官方分类检索与热门超话直达)
                  _buildDrawerItem(
                    context,
                    icon: Icons.diamond_rounded,
                    title: '超话中心',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (ctx) => const ChaohuaCenterPage()),
                      );
                    },
                  ),

                  // 8. 浏览记录
                  _buildDrawerItem(
                    context,
                    icon: Icons.history_rounded,
                    title: '浏览记录',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (ctx) => const BrowsingHistoryPage()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, size: 22),
      title: Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      visualDensity: VisualDensity.compact,
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }
}
