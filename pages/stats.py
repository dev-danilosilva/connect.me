import math

from django.contrib.auth import get_user_model
from django.db.models import Count

from .models import LinkPage


def percentile(values, pct):
    """Linear-interpolation percentile (numpy's default 'linear' method)."""
    if not values:
        return 0.0

    ordered = sorted(values)
    if len(ordered) == 1:
        return float(ordered[0])

    rank = (len(ordered) - 1) * (pct / 100)
    lower = math.floor(rank)
    upper = math.ceil(rank)
    if lower == upper:
        return float(ordered[int(rank)])

    lower_weight = ordered[lower] * (upper - rank)
    upper_weight = ordered[upper] * (rank - lower)
    return lower_weight + upper_weight


def pages_per_user_histogram(pages_per_user):
    """[{"count": N, "users": M}, ...] sorted by N, one row per distinct
    page-count value that actually occurs (no gaps filled) -- the chart
    fills gaps itself so the payload stays small.
    """
    buckets = {}
    for count in pages_per_user:
        buckets[count] = buckets.get(count, 0) + 1
    return [{"count": count, "users": buckets[count]} for count in sorted(buckets)]


def compute_dashboard_stats():
    """Aggregate stats for the staff-only admin dashboard.

    "Links" here means LinkPage rows -- the project has no separate
    per-page Link model yet, so a user's page count is the closest
    available proxy for "links created".
    """
    User = get_user_model()

    total_users = User.objects.count()
    total_pages = LinkPage.objects.count()

    pages_per_user = list(
        User.objects.annotate(page_count=Count("pages")).values_list(
            "page_count", flat=True
        )
    )

    average_pages_per_user = (total_pages / total_users) if total_users else 0.0
    p99_pages_per_user = percentile(pages_per_user, 99)

    return {
        "total_users": total_users,
        "total_pages": total_pages,
        "average_pages_per_user": average_pages_per_user,
        "p99_pages_per_user": p99_pages_per_user,
        "histogram": pages_per_user_histogram(pages_per_user),
    }
