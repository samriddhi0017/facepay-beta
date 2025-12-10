import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// On-screen debug overlay for face recognition
class FaceDebugOverlay extends StatelessWidget {
  final bool debugMode;
  final img.Image? croppedFace;
  final int embeddingLength;
  final double? similarity;
  final double? distance;
  final double threshold;
  final bool isMatch;
  final String matchedName;
  final double confidence;
  final Map<String, double>? allDistances;

  const FaceDebugOverlay({
    super.key,
    required this.debugMode,
    this.croppedFace,
    required this.embeddingLength,
    this.similarity,
    this.distance,
    required this.threshold,
    required this.isMatch,
    required this.matchedName,
    required this.confidence,
    this.allDistances,
  });

  @override
  Widget build(BuildContext context) {
    if (!debugMode) return const SizedBox.shrink();

    return Positioned(
      top: 120,
      right: 10,
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isMatch ? Colors.green : Colors.red,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Face crop preview
            if (croppedFace != null) ...[
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      Uint8List.fromList(img.encodeJpg(croppedFace!)),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(color: Colors.white30, height: 1),
              const SizedBox(height: 8),
            ],

            // Embedding info
            _buildInfoRow('Embedding:', '$embeddingLength dims'),
            const SizedBox(height: 4),

            // Similarity
            if (similarity != null)
              _buildInfoRow(
                'Similarity:',
                similarity!.toStringAsFixed(4),
                color: _getColorForSimilarity(similarity!),
              ),
            const SizedBox(height: 4),

            // Distance
            if (distance != null)
              _buildInfoRow(
                'Distance:',
                distance!.toStringAsFixed(4),
                color: _getColorForDistance(distance!),
              ),
            const SizedBox(height: 4),

            // Threshold
            _buildInfoRow(
              'Threshold:',
              threshold.toStringAsFixed(2),
              color: Colors.yellow,
            ),
            const SizedBox(height: 8),

            // Match result
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isMatch ? Colors.green : Colors.red,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isMatch ? 'MATCHED' : 'UNKNOWN',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Name and confidence
            _buildInfoRow(
              'Name:',
              matchedName,
              color: Colors.cyanAccent,
            ),
            const SizedBox(height: 4),
            _buildInfoRow(
              'Confidence:',
              '${confidence.toStringAsFixed(1)}%',
              color: _getColorForConfidence(confidence),
            ),

            // All distances (collapsed)
            if (allDistances != null && allDistances!.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Divider(color: Colors.white30, height: 1),
              const SizedBox(height: 4),
              const Text(
                'All Matches:',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              ...allDistances!.entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        e.key,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 10,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      e.value.toStringAsFixed(3),
                      style: TextStyle(
                        color: _getColorForDistance(e.value),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color ?? Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Color _getColorForSimilarity(double sim) {
    if (sim > 0.4) return Colors.green;
    if (sim > 0.2) return Colors.orange;
    return Colors.red;
  }

  Color _getColorForDistance(double dist) {
    if (dist < 0.6) return Colors.green;
    if (dist < 1.0) return Colors.orange;
    return Colors.red;
  }

  Color _getColorForConfidence(double conf) {
    if (conf > 70) return Colors.green;
    if (conf > 40) return Colors.orange;
    return Colors.red;
  }
}
