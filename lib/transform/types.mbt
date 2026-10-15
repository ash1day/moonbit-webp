///|
pub(all) enum TransformType {
  PredictorTransform(size_bits~ : Int32, data~ : FixedArray[Byte])
  ColorTransform(size_bits~ : Int32, data~ : FixedArray[Byte])
  SubtractGreen
  ColorIndexingTransform(table_size~ : Int32, data~ : FixedArray[Byte])
}
