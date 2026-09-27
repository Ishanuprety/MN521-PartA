# ---------------------------------------------------------------------------
# MN521 Part C - root module
# Availability Zones are selected here so later modules share one 2-AZ layout.
# ---------------------------------------------------------------------------

# First two available AZs in the region (2-AZ design).
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}
