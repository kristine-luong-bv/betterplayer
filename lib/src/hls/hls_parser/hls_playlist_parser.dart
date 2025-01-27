import 'dart:convert';
import 'dart:typed_data';

import 'package:better_player/src/hls/hls_parser/drm_init_data.dart';
import 'package:better_player/src/hls/hls_parser/exception.dart';
import 'package:better_player/src/hls/hls_parser/format.dart';
import 'package:better_player/src/hls/hls_parser/hls_master_playlist.dart';
import 'package:better_player/src/hls/hls_parser/hls_media_playlist.dart';
import 'package:better_player/src/hls/hls_parser/hls_track_metadata_entry.dart';
import 'package:better_player/src/hls/hls_parser/metadata.dart';
import 'package:better_player/src/hls/hls_parser/mime_types.dart';
import 'package:better_player/src/hls/hls_parser/playlist.dart';
import 'package:better_player/src/hls/hls_parser/rendition.dart';
import 'package:better_player/src/hls/hls_parser/scheme_data.dart';
import 'package:better_player/src/hls/hls_parser/segment.dart';
import 'package:better_player/src/hls/hls_parser/util.dart';
import 'package:better_player/src/hls/hls_parser/variant.dart';
import 'package:better_player/src/hls/hls_parser/variant_info.dart';
import 'package:collection/collection.dart' show IterableExtension;

class HlsPlaylistParser {
  HlsPlaylistParser(this.masterPlaylist);

  factory HlsPlaylistParser.create({HlsMasterPlaylist? masterPlaylist}) {
    masterPlaylist ??= HlsMasterPlaylist();
    return HlsPlaylistParser(masterPlaylist);
  }

  static const String playlistHeader = '#EXTM3U';
  static const String tagPrefix = '#EXT';
  static const String tagVersion = '#EXT-X-VERSION';
  static const String tagPlaylistType = '#EXT-X-PLAYLIST-TYPE';
  static const String tagDefine = '#EXT-X-DEFINE';
  static const String tagStreamInf = '#EXT-X-STREAM-INF';
  static const String tagMedia = '#EXT-X-MEDIA';
  static const String tagTargetDuration = '#EXT-X-TARGETDURATION';
  static const String tagDiscontinuity = '#EXT-X-DISCONTINUITY';
  static const String tagDiscontinuitySequence =
      '#EXT-X-DISCONTINUITY-SEQUENCE';
  static const String tagProgramDateTime = '#EXT-X-PROGRAM-DATE-TIME';
  static const String tagInitSegment = '#EXT-X-MAP';
  static const String tagIndependentSegments = '#EXT-X-INDEPENDENT-SEGMENTS';
  static const String tagMediaDuration = '#EXTINF';
  static const String tagMediaSequence = '#EXT-X-MEDIA-SEQUENCE';
  static const String tagStart = '#EXT-X-START';
  static const String tagEndList = '#EXT-X-ENDLIST';
  static const String tagKey = '#EXT-X-KEY';
  static const String tagSessionKey = '#EXT-X-SESSION-KEY';
  static const String tagByteRange = '#EXT-X-BYTERANGE';
  static const String tagGap = '#EXT-X-GAP';
  static const String typeAudio = 'AUDIO';
  static const String typeVideo = 'VIDEO';
  static const String typeSubtitles = 'SUBTITLES';
  static const String typeClosedCaptions = 'CLOSED-CAPTIONS';
  static const String methodNone = 'NONE';
  static const String methodAes128 = 'AES-128';
  static const String methodSampleAes = 'SAMPLE-AES';
  static const String methodSampleAesCenc = 'SAMPLE-AES-CENC';
  static const String methodSampleAesCtr = 'SAMPLE-AES-CTR';
  static const String keyFormatPlayReady = 'com.microsoft.playready';
  static const String keyFormatIdentity = 'identity';
  static const String keyFormatWidevinePsshBinary =
      'urn:uuid:edef8ba9-79d6-4ace-a3c8-27dcd51d21ed';
  static const String keyFormatWidevinePsshJson = 'com.widevine';
  static const String booleanTrue = 'YES';
  static const String booleanFalse = 'NO';
  static const String attrClosedCaptionsNone = 'CLOSED-CAPTIONS=NONE';
  static const String regexpAverageBandwidth = r'AVERAGE-BANDWIDTH=(\d+)\b';
  static const String regexpVideo = 'VIDEO="(.+?)"';
  static const String regexpAudio = 'AUDIO="(.+?)"';
  static const String regexpSubtitles = 'SUBTITLES="(.+?)"';
  static const String regexpClosedCaptions = 'CLOSED-CAPTIONS="(.+?)"';
  static const String regexpBandwidth = r'[^-]BANDWIDTH=(\d+)\b';
  static const String regexpChannels = 'CHANNELS="(.+?)"';
  static const String regexpCodecs = 'CODECS="(.+?)"';
  static const String regexpResolutions = r'RESOLUTION=(\d+x\d+)';
  static const String regexpFrameRate = r'FRAME-RATE=([\d\.]+)\b';
  static const String regexpTargetDuration = '$tagTargetDuration:(\\d+)\\b';
  static const String regexpVersion = '$tagVersion:(\\d+)\\b';
  static const String regexpPlaylistType = '$tagPlaylistType:(.+)\\b';
  static const String regexpMediaSequence = '$tagMediaSequence:(\\d+)\\b';
  static const String regexpMediaDuration = '$tagMediaDuration:([\\d\\.]+)\\b';
  static const String regexpMediaTitle = '$tagMediaDuration:[\\d\\.]+\\b,(.+)';
  static const String regexpTimeOffset = r'TIME-OFFSET=(-?[\d\.]+)\b';
  static const String regexpByteRange = '$tagByteRange:(\\d+(?:@\\d+)?)\\b';
  static const String regexpAttrByteRange = r'BYTERANGE="(\d+(?:@\d+)?)\b"';
  static const String regexpMethod =
      'METHOD=($methodNone|$methodAes128|$methodSampleAes|$methodSampleAesCenc|$methodSampleAesCtr)\\s*(?:,|\$)';
  static const String regexpKeyFormat = 'KEYFORMAT="(.+?)"';
  static const String regexpKeyFormatVersions = 'KEYFORMATVERSIONS="(.+?)"';
  static const String regexpUri = 'URI="(.+?)"';
  static const String regexpIv = 'IV=([^,.*]+)';
  static const String regexpType =
      'TYPE=($typeAudio|$typeVideo|$typeSubtitles|$typeClosedCaptions)';
  static const String regexpLanguage = 'LANGUAGE="(.+?)"';
  static const String regexpName = 'NAME="(.+?)"';
  static const String regexpGroupId = 'GROUP-ID="(.+?)"';
  static const String regexpCharacteristics = 'CHARACTERISTICS="(.+?)"';
  static const String regexpInStreamId = r'INSTREAM-ID="((?:CC|SERVICE)\d+)"';
  static final String
      regexpAutoSelect = // ignore: non_constant_identifier_names
      _compileBooleanAttrPattern('AUTOSELECT');

  // ignore: non_constant_identifier_names
  static final String regexpDefault = _compileBooleanAttrPattern('DEFAULT');

  // ignore: non_constant_identifier_names
  static final String regexpForced = _compileBooleanAttrPattern('FORCED');
  static const String regexpValue = 'VALUE="(.+?)"';
  static const String regexpImport = 'IMPORT="(.+?)"';
  static const String regexpVariableReference = r'\{\$([a-zA-Z0-9\-_]+)\}';

  final HlsMasterPlaylist masterPlaylist;

  Future<HlsPlaylist> parseString(Uri? uri, String inputString) async {
    final lines = const LineSplitter().convert(inputString);
    return parse(uri, lines);
  }

  Future<HlsPlaylist> parse(Uri? uri, List<String> inputLineList) async {
    final lineList = inputLineList
        .where((line) => line.trim().isNotEmpty) // ignore: always_specify_types
        .toList();

    if (!_checkPlaylistHeader(lineList[0])) {
      throw UnrecognizedInputFormatException(
          'Input does not start with the #EXTM3U header.', uri,);
    }

    final extraLines =
        lineList.getRange(1, lineList.length).toList();

    bool? isMasterPlayList;
    for (final line in extraLines) {
      if (line.startsWith(tagStreamInf)) {
        isMasterPlayList = true;
        break;
      } else if (line.startsWith(tagTargetDuration) ||
          line.startsWith(tagMediaSequence) ||
          line.startsWith(tagMediaDuration) ||
          line.startsWith(tagKey) ||
          line.startsWith(tagByteRange) ||
          line == tagDiscontinuity ||
          line == tagDiscontinuitySequence ||
          line == tagEndList) {
        isMasterPlayList = false;
      }
    }
    if (isMasterPlayList == null) {
      throw const FormatException("extraLines doesn't have valid tag");
    }

    return isMasterPlayList
        ? _parseMasterPlaylist(extraLines.iterator, uri.toString())
        : _parseMediaPlaylist(masterPlaylist, extraLines, uri.toString());
  }

  static String _compileBooleanAttrPattern(String attribute) =>
      '$attribute=($booleanFalse|$booleanTrue)';

  static bool _checkPlaylistHeader(String string) {
    var codeUnits = LibUtil.excludeWhiteSpace(string).codeUnits;

    if (codeUnits[0] == 0xEF) {
      if (LibUtil.startsWith(codeUnits, [0xEF, 0xBB, 0xBF])) {
        return false;
      }
      codeUnits =
          codeUnits.getRange(5, codeUnits.length - 1).toList(); //不要な文字が含まれている
    }

    if (!LibUtil.startsWith(codeUnits, playlistHeader.runes.toList())) {
      return false;
    }

    return true;
  }

  HlsMasterPlaylist _parseMasterPlaylist(
      Iterator<String> extraLines, String baseUri,) {
    final tags = <String>[]; // ignore: always_specify_types
    final mediaTags = <String>[]; // ignore: always_specify_types
    final sessionKeyDrmInitData =
        <DrmInitData>[]; // ignore: always_specify_types
    final variants = <Variant>[]; // ignore: always_specify_types
    final videos = <Rendition>[]; // ignore: always_specify_types
    final audios = <Rendition>[]; // ignore: always_specify_types
    final subtitles = <Rendition>[]; // ignore: always_specify_types
    final closedCaptions = <Rendition>[]; // ignore: always_specify_types
    final urlToVariantInfos =
        <Uri, List<VariantInfo>>{}; // ignore: always_specify_types
    Format? muxedAudioFormat;
    var noClosedCaptions = false;
    var hasIndependentSegmentsTag = false;
    List<Format>? muxedCaptionFormats;

    final variableDefinitions =
        <String?, String>{}; // ignore: always_specify_types

    while (extraLines.moveNext()) {
      final line = extraLines.current;

      if (line.startsWith(tagDefine)) {
        final key = _parseStringAttr(
            source: line,
            pattern: regexpName,
            variableDefinitions: variableDefinitions,);
        final val = _parseStringAttr(
            source: line,
            pattern: regexpValue,
            variableDefinitions: variableDefinitions,);
        if (key == null) {
          throw ParserException("Couldn't match $regexpName in $line");
        }
        if (val == null) {
          throw ParserException("Couldn't match $regexpValue in $line");
        }
        variableDefinitions[key] = val;
      } else if (line == tagIndependentSegments) {
        hasIndependentSegmentsTag = true;
      } else if (line.startsWith(tagMedia)) {
        mediaTags.add(line);
      } else if (line.startsWith(tagSessionKey)) {
        final keyFormat = _parseStringAttr(
            source: line,
            pattern: regexpKeyFormat,
            defaultValue: keyFormatIdentity,
            variableDefinitions: variableDefinitions,);
        final schemeData = _parseDrmSchemeData(
            line: line,
            keyFormat: keyFormat,
            variableDefinitions: variableDefinitions,);

        if (schemeData != null) {
          final method = _parseStringAttr(
              source: line,
              pattern: regexpMethod,
              variableDefinitions: variableDefinitions,);
          final scheme = _parseEncryptionScheme(method);
          final drmInitData = DrmInitData(
              schemeType: scheme,
              schemeData: [schemeData],); // ignore: always_specify_types
          sessionKeyDrmInitData.add(drmInitData);
        }
      } else if (line.startsWith(tagStreamInf)) {
        noClosedCaptions |= line.contains(attrClosedCaptionsNone); //todo 再検討
        final bitrate = int.parse(
            _parseStringAttr(source: line, pattern: regexpBandwidth)!,);
        var averageBitrate = 0;
        final averageBandwidthString = _parseStringAttr(
            source: line,
            pattern: regexpAverageBandwidth,
            variableDefinitions: variableDefinitions,);
        if (averageBandwidthString != null) {
          averageBitrate = int.parse(averageBandwidthString);
        }
        final codecs = _parseStringAttr(
            source: line,
            pattern: regexpCodecs,
            variableDefinitions: variableDefinitions,);
        final resolutionString = _parseStringAttr(
            source: line,
            pattern: regexpResolutions,
            variableDefinitions: variableDefinitions,);
        int? width;
        int? height;
        if (resolutionString != null) {
          final widthAndHeight = resolutionString.split('x');
          width = int.parse(widthAndHeight[0]);
          height = int.parse(widthAndHeight[1]);
          if (width <= 0 || height <= 0) {
            // Resolution string is invalid.
            width = null;
            height = null;
          }
        }

        double? frameRate;
        final frameRateString = _parseStringAttr(
            source: line,
            pattern: regexpFrameRate,
            variableDefinitions: variableDefinitions,);
        if (frameRateString != null) {
          frameRate = double.parse(frameRateString);
        }
        final videoGroupId = _parseStringAttr(
            source: line,
            pattern: regexpVideo,
            variableDefinitions: variableDefinitions,);
        final audioGroupId = _parseStringAttr(
            source: line,
            pattern: regexpAudio,
            variableDefinitions: variableDefinitions,);
        final subtitlesGroupId = _parseStringAttr(
            source: line,
            pattern: regexpSubtitles,
            variableDefinitions: variableDefinitions,);
        final closedCaptionsGroupId = _parseStringAttr(
            source: line,
            pattern: regexpClosedCaptions,
            variableDefinitions: variableDefinitions,);

        extraLines.moveNext();

        final referenceUri = _parseStringAttr(
            source: extraLines.current,
            variableDefinitions: variableDefinitions,)!;
        final uri = Uri.parse(baseUri).resolve(referenceUri);

        final format = Format.createVideoContainerFormat(
            id: variants.length.toString(),
            containerMimeType: MimeTypes.applicationM3u8,
            codecs: codecs,
            bitrate: bitrate,
            averageBitrate: averageBitrate,
            width: width,
            height: height,
            frameRate: frameRate,);

        variants.add(Variant(
          url: uri,
          format: format,
          videoGroupId: videoGroupId,
          audioGroupId: audioGroupId,
          subtitleGroupId: subtitlesGroupId,
          captionGroupId: closedCaptionsGroupId,
        ),);

        var variantInfosForUrl = urlToVariantInfos[uri];
        if (variantInfosForUrl == null) {
          variantInfosForUrl = []; // ignore: always_specify_types
          urlToVariantInfos[uri] = variantInfosForUrl;
        }

        variantInfosForUrl.add(VariantInfo(
          bitrate: bitrate != 0 ? bitrate : averageBitrate,
          videoGroupId: videoGroupId,
          audioGroupId: audioGroupId,
          subtitleGroupId: subtitlesGroupId,
          captionGroupId: closedCaptionsGroupId,
        ),);
      }
    }

    // TODO: Don't deduplicate variants by URL.
    final deduplicatedVariants =
        <Variant>[]; // ignore: always_specify_types
    final urlsInDeduplicatedVariants =
        <Uri>{}; // ignore: always_specify_types
    for (var i = 0; i < variants.length; i++) {
      final variant = variants[i];
      if (urlsInDeduplicatedVariants.add(variant.url)) {
        assert(variant.format.metadata == null);
        final hlsMetadataEntry =
            HlsTrackMetadataEntry(variantInfos: urlToVariantInfos[variant.url]);
        final metadata = Metadata([hlsMetadataEntry]);
        deduplicatedVariants.add(
            variant.copyWithFormat(variant.format.copyWithMetadata(metadata)),);
      }
    }

    // ignore: always_specify_types
    mediaTags.forEach((line) {
      final groupId = _parseStringAttr(
          source: line,
          pattern: regexpGroupId,
          variableDefinitions: variableDefinitions,);
      final name = _parseStringAttr(
          source: line,
          pattern: regexpName,
          variableDefinitions: variableDefinitions,);
      final referenceUri = _parseStringAttr(
          source: line,
          pattern: regexpUri,
          variableDefinitions: variableDefinitions,);

      var uri = Uri.parse(baseUri);
      if (referenceUri != null) uri = uri.resolve(referenceUri);

      final language = _parseStringAttr(
          source: line,
          pattern: regexpLanguage,
          variableDefinitions: variableDefinitions,);
      final selectionFlags = _parseSelectionFlags(line);
      final roleFlags = _parseRoleFlags(line, variableDefinitions);
      final formatId = '$groupId:$name';
      Format format;
      final entry = HlsTrackMetadataEntry(
          groupId: groupId, name: name, variantInfos: <VariantInfo>[],);
      final metadata = Metadata([entry]);

      switch (_parseStringAttr(
          source: line,
          pattern: regexpType,
          variableDefinitions: variableDefinitions,)) {
        case typeVideo:
          {
            final variant =
                variants.firstWhereOrNull((it) => it.videoGroupId == groupId);
            String? codecs;
            int? width;
            int? height;
            double? frameRate;
            if (variant != null) {
              final variantFormat = variant.format;
              codecs = LibUtil.getCodecsOfType(
                  variantFormat.codecs, Util.trackTypeVideo,);
              width = variantFormat.width;
              height = variantFormat.height;
              frameRate = variantFormat.frameRate;
            }
            final sampleMimeType =
                codecs != null ? MimeTypes.getMediaMimeType(codecs) : null;

            format = Format.createVideoContainerFormat(
                    id: formatId,
                    label: name,
                    containerMimeType: MimeTypes.applicationM3u8,
                    sampleMimeType: sampleMimeType,
                    codecs: codecs,
                    width: width,
                    height: height,
                    frameRate: frameRate,
                    selectionFlags: selectionFlags,
                    roleFlags: roleFlags,)
                .copyWithMetadata(metadata);

            videos.add(Rendition(
              url: uri,
              format: format,
              groupId: groupId,
              name: name,
            ),);
            break;
          }
        case typeAudio:
          {
            final variant =
                _getVariantWithAudioGroup(variants, groupId);
            final codecs = variant != null
                ? LibUtil.getCodecsOfType(
                    variant.format.codecs, Util.trackTypeAudio,)
                : null;
            final channelCount =
                _parseChannelsAttribute(line, variableDefinitions);
            final sampleMimeType =
                codecs != null ? MimeTypes.getMediaMimeType(codecs) : null;
            final format = Format(
              id: formatId,
              label: name,
              containerMimeType: MimeTypes.applicationM3u8,
              sampleMimeType: sampleMimeType,
              codecs: codecs,
              channelCount: channelCount,
              selectionFlags: selectionFlags,
              roleFlags: roleFlags,
              language: language,
            );

            // ignore: unnecessary_null_comparison
            if (uri == null) {
              muxedAudioFormat = format;
            } else {
              audios.add(Rendition(
                url: uri,
                format: format.copyWithMetadata(metadata),
                groupId: groupId,
                name: name,
              ),);
            }
            break;
          }
        case typeSubtitles:
          {
            final format = Format(
                    id: formatId,
                    label: name,
                    containerMimeType: MimeTypes.applicationM3u8,
                    sampleMimeType: MimeTypes.textVtt,
                    selectionFlags: selectionFlags,
                    roleFlags: roleFlags,
                    language: language,)
                .copyWithMetadata(metadata);
            subtitles.add(Rendition(
              url: uri,
              format: format,
              groupId: groupId,
              name: name,
            ),);
            break;
          }
        case typeClosedCaptions:
          {
            final instreamId = _parseStringAttr(
                source: line,
                pattern: regexpInStreamId,
                variableDefinitions: variableDefinitions,)!;
            String mimeType;
            int accessibilityChannel;
            if (instreamId.startsWith('CC')) {
              mimeType = MimeTypes.applicationCea608;
              accessibilityChannel = int.parse(instreamId.substring(2));
            } else /* starts with SERVICE */ {
              mimeType = MimeTypes.applicationCea708;
              accessibilityChannel = int.parse(instreamId.substring(7));
            }
            muxedCaptionFormats ??= []; // ignore: always_specify_types
            muxedCaptionFormats!.add(Format(
              id: formatId,
              label: name,
              sampleMimeType: mimeType,
              selectionFlags: selectionFlags,
              roleFlags: roleFlags,
              language: language,
              accessibilityChannel: accessibilityChannel,
            ),);
            break;
          }
        default:
          break;
      }
    });

    if (noClosedCaptions) {
      muxedCaptionFormats = [];
    } // ignore: always_specify_types

    return HlsMasterPlaylist(
        baseUri: baseUri,
        tags: tags,
        variants: deduplicatedVariants,
        videos: videos,
        audios: audios,
        subtitles: subtitles,
        closedCaptions: closedCaptions,
        muxedAudioFormat: muxedAudioFormat,
        muxedCaptionFormats: muxedCaptionFormats,
        hasIndependentSegments: hasIndependentSegmentsTag,
        variableDefinitions: variableDefinitions,
        sessionKeyDrmInitData: sessionKeyDrmInitData,);
  }

  static String? _parseStringAttr({
    required String? source,
    String? pattern,
    String? defaultValue,
    Map<String?, String?>? variableDefinitions,
  }) {
    String? value;
    if (pattern == null) {
      value = source;
    } else {
      value = RegExp(pattern).firstMatch(source!)?.group(1);
      value ??= defaultValue;
    }

    return value?.replaceAllMapped(
        RegExp(regexpVariableReference),
        (Match match) => variableDefinitions![match.group(1)] ??=
            value!.substring(match.start, match.end),);
  }

  static SchemeData? _parseDrmSchemeData(
      {String? line,
      String? keyFormat,
      Map<String?, String?>? variableDefinitions,}) {
    final keyFormatVersions = _parseStringAttr(
      source: line,
      pattern: regexpKeyFormatVersions,
      defaultValue: '1',
      variableDefinitions: variableDefinitions,
    );

    if (keyFormatWidevinePsshBinary == keyFormat) {
      final uriString = _parseStringAttr(
          source: line,
          pattern: regexpUri,
          variableDefinitions: variableDefinitions,)!;
      final data = _getBase64FromUri(uriString);
      return SchemeData(
//          uuid: '', //todo 保留
          mimeType: MimeTypes.videoMp4,
          data: data,);
    } else if (keyFormatWidevinePsshJson == keyFormat) {
      return SchemeData(
//          uuid: '', //todo 保留
          mimeType: MimeTypes.hls,
          data: const Utf8Encoder().convert(line!),);
    } else if (keyFormatPlayReady == keyFormat && '1' == keyFormatVersions) {
      final uriString = _parseStringAttr(
          source: line,
          pattern: regexpUri,
          variableDefinitions: variableDefinitions,)!;
      final data = _getBase64FromUri(uriString);
//      Uint8List psshData; //todo 保留
      return SchemeData(mimeType: MimeTypes.videoMp4, data: data);
    }

    return null;
  }

  static int _parseSelectionFlags(String line) {
    var flags = 0;

    if (parseOptionalBooleanAttribute(
        line: line,
        pattern: regexpDefault,
        defaultValue: false,)) flags |= Util.selectionFlagDefault;
    if (parseOptionalBooleanAttribute(
        line: line,
        pattern: regexpForced,
        defaultValue: false,)) flags |= Util.selectionFlagForced;
    if (parseOptionalBooleanAttribute(
        line: line,
        pattern: regexpAutoSelect,
        defaultValue: false,)) flags |= Util.selectionFlagAutoSelect;
    return flags;
  }

  static bool parseOptionalBooleanAttribute({
    required String line,
    required String pattern,
    required bool defaultValue,
  }) {
    final regExp = RegExp(pattern);
    final List<Match> list = regExp.allMatches(line).toList();
    final ret = list.isEmpty
        ? defaultValue
        : line
            .substring(list.first.start, list.first.end)
            .contains(booleanTrue);
    return ret;
  }

  static int _parseRoleFlags(
      String line, Map<String?, String> variableDefinitions,) {
    final concatenatedCharacteristics = _parseStringAttr(
        source: line,
        pattern: regexpCharacteristics,
        variableDefinitions: variableDefinitions,);
    if (concatenatedCharacteristics?.isEmpty != false) return 0;
    final characteristics =
        concatenatedCharacteristics!.split(',');
    var roleFlags = 0;
    if (characteristics.contains('public.accessibility.describes-video')) {
      roleFlags |= Util.roleFlagDescribesVideo;
    }

    if (characteristics
        .contains('public.accessibility.transcribes-spoken-dialog')) {
      roleFlags |= Util.roleFlagTranscribesDialog;
    }

    if (characteristics
        .contains('public.accessibility.describes-music-and-sound')) {
      roleFlags |= Util.roleFlagDescribesMusicAndSound;
    }

    if (characteristics.contains('public.easy-to-read')) {
      roleFlags |= Util.roleFlagEasyToRead;
    }

    return roleFlags;
  }

  static int? _parseChannelsAttribute(
      String line, Map<String?, String> variableDefinitions,) {
    final channelsString = _parseStringAttr(
        source: line,
        pattern: regexpChannels,
        variableDefinitions: variableDefinitions,);
    return channelsString != null
        ? int.parse(channelsString.split('/')[0])
        : null;
  }

  static Variant? _getVariantWithAudioGroup(
      List<Variant> variants, String? groupId,) {
    for (final variant in variants) {
      if (variant.audioGroupId == groupId) return variant;
    }
    return null;
  }

  static String _parseEncryptionScheme(String? method) =>
      methodSampleAesCenc == method || methodSampleAesCtr == method
          ? CencType.cenc
          : CencType.cnbs;

  static Uint8List _getBase64FromUri(String uriString) {
    final uriPre = uriString.substring(uriString.indexOf(',') + 1);
    return const Base64Decoder().convert(uriPre);
  }

  static HlsMediaPlaylist _parseMediaPlaylist(HlsMasterPlaylist masterPlaylist,
      List<String> extraLines, String baseUri,) {
    var playlistType = HlsMediaPlaylist.playlistTypeUnknown;
    int? startOffsetUs;
    int? mediaSequence;
    int? version;
    int? targetDurationUs;
    var hasIndependentSegmentsTag = masterPlaylist.hasIndependentSegments;
    var hasEndTag = false;
    int? segmentByteRangeOffset;
    Segment? initializationSegment;
    final variableDefinitions = <String?, String?>{};
    final segments = <Segment>[];
    final tags = <String>[]; // ignore: always_specify_types
    int? segmentByteRangeLength;
    int? segmentMediaSequence = 0;
    int? segmentDurationUs;
    String? segmentTitle;
    final currentSchemeDatas =
        <String?, SchemeData>{}; // ignore: always_specify_types
    DrmInitData? cachedDrmInitData;
    String? encryptionScheme;
    DrmInitData? playlistProtectionSchemes;
    var hasDiscontinuitySequence = false;
    var playlistDiscontinuitySequence = 0;
    int? relativeDiscontinuitySequence;
    int? playlistStartTimeUs;
    int? segmentStartTimeUs;
    var hasGapTag = false;

    String? fullSegmentEncryptionKeyUri;
    String? fullSegmentEncryptionIV;

    for (final line in extraLines) {
      if (line.startsWith(tagPrefix)) {
        // We expose all tags through the playlist.
        tags.add(line);
      }

      if (line.startsWith(tagPlaylistType)) {
        final playlistTypeString = _parseStringAttr(
            source: line,
            pattern: regexpPlaylistType,
            variableDefinitions: variableDefinitions,);
        if ('VOD' == playlistTypeString) {
          playlistType = HlsMediaPlaylist.playlistTypeVod;
        } else if ('EVENT' == playlistTypeString) {
          playlistType = HlsMediaPlaylist.playlistTypeEvent;
        }
      } else if (line.startsWith(tagStart)) {
        final string = _parseStringAttr(
            source: line,
            pattern: regexpTimeOffset,
            variableDefinitions: {},)!; // ignore: always_specify_types
        startOffsetUs = (double.parse(string) * 1000000).toInt();
      } else if (line.startsWith(tagInitSegment)) {
        final uri = _parseStringAttr(
            source: line,
            pattern: regexpUri,
            variableDefinitions: variableDefinitions,);
        final byteRange = _parseStringAttr(
            source: line,
            pattern: regexpAttrByteRange,
            variableDefinitions: variableDefinitions,);
        if (byteRange != null) {
          final splitByteRange = byteRange.split('@');
          segmentByteRangeLength = int.parse(splitByteRange[0]);
          if (splitByteRange.length > 1) {
            segmentByteRangeOffset = int.parse(splitByteRange[1]);
          }
        }

        if (fullSegmentEncryptionKeyUri != null &&
            fullSegmentEncryptionIV == null) {
          throw ParserException(
              'The encryption IV attribute must be present when an initialization segment is encrypted with METHOD=AES-128.',);
        }

        initializationSegment = Segment(
            url: uri,
            byterangeOffset: segmentByteRangeOffset,
            byterangeLength: segmentByteRangeLength,
            fullSegmentEncryptionKeyUri: fullSegmentEncryptionKeyUri,
            encryptionIV: fullSegmentEncryptionIV,);
        segmentByteRangeOffset = null;
        segmentByteRangeLength = null;
      } else if (line.startsWith(tagTargetDuration)) {
        targetDurationUs = int.parse(_parseStringAttr(
                source: line, pattern: regexpTargetDuration,)!,) *
            1000000;
      } else if (line.startsWith(tagMediaSequence)) {
        mediaSequence = int.parse(
            _parseStringAttr(source: line, pattern: regexpMediaSequence)!,);
        segmentMediaSequence = mediaSequence;
      } else if (line.startsWith(tagVersion)) {
        version =
            int.parse(_parseStringAttr(source: line, pattern: regexpVersion)!);
      } else if (line.startsWith(tagDefine)) {
        final importName = _parseStringAttr(
            source: line,
            pattern: regexpImport,
            variableDefinitions: variableDefinitions,);
        if (importName != null) {
          final value = masterPlaylist.variableDefinitions[importName];
          if (value != null) {
            variableDefinitions[importName] = value;
          } else {
            // The master playlist does not declare the imported variable. Ignore.
          }
        } else {
          final key = _parseStringAttr(
              source: line,
              pattern: regexpName,
              variableDefinitions: variableDefinitions,);
          final value = _parseStringAttr(
              source: line,
              pattern: regexpValue,
              variableDefinitions: variableDefinitions,);
          variableDefinitions[key] = value;
        }
      } else if (line.startsWith(tagMediaDuration)) {
        final string =
            _parseStringAttr(source: line, pattern: regexpMediaDuration)!;
        segmentDurationUs = (double.parse(string) * 1000000).toInt();
        segmentTitle = _parseStringAttr(
            source: line,
            pattern: regexpMediaTitle,
            defaultValue: '',
            variableDefinitions: variableDefinitions,);
      } else if (line.startsWith(tagKey)) {
        final method = _parseStringAttr(
            source: line,
            pattern: regexpMethod,
            variableDefinitions: variableDefinitions,);
        final keyFormat = _parseStringAttr(
            source: line,
            pattern: regexpKeyFormat,
            defaultValue: keyFormatIdentity,
            variableDefinitions: variableDefinitions,);
        fullSegmentEncryptionKeyUri = null;
        fullSegmentEncryptionIV = null;
        if (methodNone == method) {
          currentSchemeDatas.clear();
          cachedDrmInitData = null;
        } else /* !METHOD_NONE.equals(method) */ {
          fullSegmentEncryptionIV = _parseStringAttr(
              source: line,
              pattern: regexpIv,
              variableDefinitions: variableDefinitions,);
          if (keyFormatIdentity == keyFormat) {
            if (methodAes128 == method) {
              // The segment is fully encrypted using an identity key.
              fullSegmentEncryptionKeyUri = _parseStringAttr(
                  source: line,
                  pattern: regexpUri,
                  variableDefinitions: variableDefinitions,);
            } else {
              // Do nothing. Samples are encrypted using an identity key, but this is not supported.
              // Hopefully, a traditional DRM alternative is also provided.
            }
          } else {
            encryptionScheme ??= _parseEncryptionScheme(method);
            final schemeData = _parseDrmSchemeData(
                line: line,
                keyFormat: keyFormat,
                variableDefinitions: variableDefinitions,);
            if (schemeData != null) {
              cachedDrmInitData = null;
              currentSchemeDatas[keyFormat] = schemeData;
            }
          }
        }
      } else if (line.startsWith(tagByteRange)) {
        final byteRange = _parseStringAttr(
            source: line,
            pattern: regexpByteRange,
            variableDefinitions: variableDefinitions,)!;
        final splitByteRange = byteRange.split('@');
        segmentByteRangeLength = int.parse(splitByteRange[0]);
        if (splitByteRange.length > 1) {
          segmentByteRangeOffset = int.parse(splitByteRange[1]);
        }
      } else if (line.startsWith(tagDiscontinuitySequence)) {
        hasDiscontinuitySequence = true;
        playlistDiscontinuitySequence =
            int.parse(line.substring(line.indexOf(':') + 1));
      } else if (line == tagDiscontinuity) {
        relativeDiscontinuitySequence ??= 0;
        relativeDiscontinuitySequence++;
      } else if (line.startsWith(tagProgramDateTime)) {
        if (playlistStartTimeUs == null) {
          final programDatetimeUs =
              LibUtil.parseXsDateTime(line.substring(line.indexOf(':') + 1));
          playlistStartTimeUs = programDatetimeUs - (segmentStartTimeUs ?? 0);
        }
      } else if (line == tagGap) {
        hasGapTag = true;
      } else if (line == tagIndependentSegments) {
        hasIndependentSegmentsTag = true;
      } else if (line == tagEndList) {
        hasEndTag = true;
      } else if (!line.startsWith('#')) {
        String? segmentEncryptionIV;
        if (fullSegmentEncryptionKeyUri == null) {
          segmentEncryptionIV = null;
        } else if (fullSegmentEncryptionIV != null) {
          segmentEncryptionIV = fullSegmentEncryptionIV;
        } else {
          segmentEncryptionIV = segmentMediaSequence!.toRadixString(16);
        }
        segmentMediaSequence = segmentMediaSequence! + 1;

        if (segmentByteRangeLength == null) segmentByteRangeOffset = null;

        if (cachedDrmInitData?.schemeData.isNotEmpty != true &&
            currentSchemeDatas.isNotEmpty) {
          final schemeDatas =
              currentSchemeDatas.values.toList();
          cachedDrmInitData = DrmInitData(
              schemeType: encryptionScheme, schemeData: schemeDatas,);
          if (playlistProtectionSchemes == null) {
            final playlistSchemeDatas =
                schemeDatas.map((it) => it.copyWithData(null)).toList();
            playlistProtectionSchemes = DrmInitData(
                schemeType: encryptionScheme, schemeData: playlistSchemeDatas,);
          }
        }

        final url = _parseStringAttr(
            source: line, variableDefinitions: variableDefinitions,);
        segments.add(Segment(
            url: url,
            initializationSegment: initializationSegment,
            title: segmentTitle,
            durationUs: segmentDurationUs,
            relativeDiscontinuitySequence: relativeDiscontinuitySequence,
            relativeStartTimeUs: segmentStartTimeUs,
            drmInitData: cachedDrmInitData,
            fullSegmentEncryptionKeyUri: fullSegmentEncryptionKeyUri,
            encryptionIV: segmentEncryptionIV,
            byterangeOffset: segmentByteRangeOffset,
            byterangeLength: segmentByteRangeLength,
            hasGapTag: hasGapTag,),);

        if (segmentDurationUs != null) {
          segmentStartTimeUs ??= 0;
          segmentStartTimeUs += segmentDurationUs;
        }
        segmentDurationUs = null;
        segmentTitle = null;
        if (segmentByteRangeLength != null) {
          segmentByteRangeOffset ??= 0;
          segmentByteRangeOffset += segmentByteRangeLength;
        }

        segmentByteRangeLength = null;
        hasGapTag = false;
      }
    }

    return HlsMediaPlaylist.create(
        playlistType: playlistType,
        baseUri: baseUri,
        tags: tags,
        startOffsetUs: startOffsetUs,
        startTimeUs: playlistStartTimeUs,
        hasDiscontinuitySequence: hasDiscontinuitySequence,
        discontinuitySequence: playlistDiscontinuitySequence,
        mediaSequence: mediaSequence,
        version: version,
        targetDurationUs: targetDurationUs,
        hasIndependentSegments: hasIndependentSegmentsTag,
        hasEndTag: hasEndTag,
        hasProgramDateTime: playlistStartTimeUs != null,
        protectionSchemes: playlistProtectionSchemes,
        segments: segments,);
  }
}
