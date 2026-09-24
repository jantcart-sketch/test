output "tf_state_bucket" {
  value = aws_s3_bucket.tfstate.bucket
}

output "tf_state_lock_table" {
  value = aws_dynamodb_table.tfstate_lock.name
}
