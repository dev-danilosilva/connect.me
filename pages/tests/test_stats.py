import pytest

from accounts.models import User
from pages.models import LinkPage
from pages.stats import compute_dashboard_stats, pages_per_user_histogram, percentile

pytestmark = pytest.mark.django_db


class TestPercentile:
    def test_empty_list_returns_zero(self):
        assert percentile([], 99) == 0.0

    def test_single_value_returns_that_value(self):
        assert percentile([7], 99) == 7.0

    def test_matches_numpy_linear_method_example(self):
        # Known reference values for the "linear" interpolation method.
        values = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        assert percentile(values, 50) == pytest.approx(5.5)
        assert percentile(values, 100) == 10.0
        assert percentile(values, 0) == 1.0

    def test_p99_of_mostly_zero_distribution_is_pulled_by_the_outlier(self):
        values = [0] * 98 + [50]
        result = percentile(values, 99)
        assert 0 < result <= 50


class TestPagesPerUserHistogram:
    def test_empty_input_gives_empty_histogram(self):
        assert pages_per_user_histogram([]) == []

    def test_buckets_by_count_sorted_ascending(self):
        result = pages_per_user_histogram([0, 0, 2, 1, 2, 2])
        assert result == [
            {"count": 0, "users": 2},
            {"count": 1, "users": 1},
            {"count": 2, "users": 3},
        ]


class TestComputeDashboardStats:
    def test_no_users_gives_zeroed_stats(self):
        stats = compute_dashboard_stats()
        assert stats == {
            "total_users": 0,
            "total_pages": 0,
            "average_pages_per_user": 0.0,
            "p99_pages_per_user": 0.0,
            "histogram": [],
        }

    def test_counts_and_average_across_users_with_and_without_pages(self):
        alice = User.objects.create_user(email="alice@example.com", password="password123")
        User.objects.create_user(email="bob@example.com", password="password123")
        LinkPage.objects.create(owner=alice, handle="alice-one")
        LinkPage.objects.create(owner=alice, handle="alice-two")

        stats = compute_dashboard_stats()

        assert stats["total_users"] == 2
        assert stats["total_pages"] == 2
        # Bob has 0 pages, Alice has 2 -> average over ALL users, not just
        # users who created a page.
        assert stats["average_pages_per_user"] == pytest.approx(1.0)

    def test_p99_reflects_a_heavy_user_among_many_light_users(self):
        heavy_user = User.objects.create_user(email="heavy@example.com", password="password123")
        for i in range(5):
            LinkPage.objects.create(owner=heavy_user, handle=f"heavy-{i}")

        for i in range(20):
            light_user = User.objects.create_user(
                email=f"light{i}@example.com", password="password123"
            )
            LinkPage.objects.create(owner=light_user, handle=f"light-{i}")

        stats = compute_dashboard_stats()
        assert stats["total_users"] == 21
        assert stats["total_pages"] == 25
        assert stats["p99_pages_per_user"] >= stats["average_pages_per_user"]
