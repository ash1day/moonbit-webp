///|
pub(all) enum TransformType {
  PredictorTransform(size_bits~ : Int, data~ : FixedArray[Byte])
  ColorTransform(size_bits~ : Int, data~ : FixedArray[Byte])
  SubtractGreen
  ColorIndexingTransform(table_size~ : Int, data~ : FixedArray[Byte])
}
