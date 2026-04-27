# Terraform Infrastructure

This folder contains both:

- `backend-bootstrap.tf`: creates the S3 bucket and DynamoDB table used by Terraform remote state.
- `backend.tf`: configures Terraform to use that S3 backend and DynamoDB lock table.

Because these live in the same root module, first-time setup requires a one-time bootstrap flow.

## First-Time Bootstrap (No Existing Remote State)

1. Temporarily disable the S3 backend config by renaming `backend.tf`:

```bash
mv backend.tf backend.tf.disabled
```

2. Initialize and apply with the default local backend:

```bash
terraform init
terraform apply
```

3. Re-enable the backend config:

```bash
mv backend.tf.disabled backend.tf
```

4. Re-initialize and migrate local state to S3:

```bash
terraform init -migrate-state
```

5. Verify state now points to the remote backend:

```bash
terraform state list
```

## Normal Workflow (After Bootstrap)

Once the backend is bootstrapped, use normal Terraform commands:

```bash
terraform plan
terraform apply
```

## Notes

- Run these commands from the `infra` directory.
- If backend resource names change in `backend-bootstrap.tf`, update `backend.tf` to match.
