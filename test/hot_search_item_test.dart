import 'package:flutter_test/flutter_test.dart';
import 'package:review/features/search/data/search_repository.dart';
import 'package:review/features/search/presentation/hot_trends_view.dart';
import 'package:review/core/constants/api_constants.dart';

void main() {
  test('parses fields returned by web hot-trend endpoints', () {
    final item = HotSearchItem.fromJson(
      {
        'rank': 3,
        'realpos': 4,
        'word': '网页端分类榜单词条',
        'description': 12345,
        'icon_desc': '新',
        'm_category': '科技',
      },
      0,
    );

    expect(item.rank, 4);
    expect(item.word, '网页端分类榜单词条');
    expect(item.num, 12345);
    expect(item.labelName, '新');
    expect(item.category, '科技');
    expect(item.isNew, isTrue);
    expect(item.isRanked, isTrue);
  });

  test('marks unranked location topics without treating description as a count', () {
    final item = HotSearchItem.fromJson(
      {
        'word': '广州医生边聊天边救出患者脑里9年活虫',
        'description': '广州',
      },
      6,
    );

    expect(item.isRanked, isFalse);
    expect(item.locationLabel, '广州');
    expect(item.num, 0);
  });

  test('supports separately returned pinned hot topics', () {
    final item = HotSearchItem.fromJson(
      {'word': '置顶热搜'},
      0,
      isPinned: true,
    );

    expect(item.isPinned, isTrue);
    expect(item.isRanked, isFalse);
    expect(item.locationLabel, isNull);
  });

  test('maps only boards that exist in the web hot-trend navigation', () {
    expect(ApiConstants.hotTrendCategoryEndpoints['mine'], ApiConstants.hotMine);
    expect(ApiConstants.hotTrendCategoryEndpoints['hot'], ApiConstants.hotSearch);
    expect(ApiConstants.hotTrendCategoryEndpoints['ent'], ApiConstants.hotEntertainment);
    expect(ApiConstants.hotTrendCategoryEndpoints['social'], ApiConstants.hotSocial);
    expect(ApiConstants.hotTrendCategoryEndpoints['tech'], ApiConstants.hotTechnology);
    expect(ApiConstants.hotTrendCategoryEndpoints['life'], ApiConstants.hotLife);
    expect(ApiConstants.hotTrendCategoryEndpoints['sports'], ApiConstants.hotSport);
    expect(ApiConstants.hotTrendCategoryEndpoints['acg'], ApiConstants.hotAcg);
    expect(ApiConstants.hotTrendCategoryEndpoints.containsKey('local'), isFalse);
  });

  test('hot trends page remains constructible after using web categories', () {
    expect(const HotTrendsView(), isA<HotTrendsView>());
  });
}
