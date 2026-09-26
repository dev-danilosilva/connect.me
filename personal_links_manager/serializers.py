from rest_framework import serializers

from .models import Block, LinkPage


class LinkDataSerializer(serializers.Serializer):
    label = serializers.CharField(max_length=150)
    url = serializers.URLField()


class HeaderDataSerializer(serializers.Serializer):
    display_name = serializers.CharField(max_length=150)
    bio = serializers.CharField(max_length=500, required=False, allow_blank=True)
    avatar_url = serializers.CharField(required=False, allow_blank=True)


class SocialIconDataSerializer(serializers.Serializer):
    platform = serializers.CharField(max_length=50)
    url = serializers.URLField()


class SocialIconsDataSerializer(serializers.Serializer):
    icons = SocialIconDataSerializer(many=True)


BLOCK_DATA_SERIALIZERS = {
    Block.BlockType.LINK: LinkDataSerializer,
    Block.BlockType.HEADER: HeaderDataSerializer,
    Block.BlockType.SOCIAL_ICONS: SocialIconsDataSerializer,
}


class BlockSerializer(serializers.ModelSerializer):
    class Meta:
        model = Block
        fields = ["id", "block_type", "position", "visible", "data"]
        read_only_fields = ["id", "position"]

    def validate(self, attrs):
        block_type = attrs.get("block_type", getattr(self.instance, "block_type", None))
        data = attrs.get("data")
        if data is not None:
            data_serializer_cls = BLOCK_DATA_SERIALIZERS[block_type]
            data_serializer = data_serializer_cls(data=data)
            if not data_serializer.is_valid():
                raise serializers.ValidationError({"data": data_serializer.errors})
            attrs["data"] = data_serializer.validated_data
        return attrs


class LinkPageSerializer(serializers.ModelSerializer):
    blocks = BlockSerializer(many=True, read_only=True)

    class Meta:
        model = LinkPage
        fields = ["id", "handle", "title", "blocks"]
