terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region     = "us-east-1"
  access_key = "ASIAVFOZOECNZ4QQNMXM"
  secret_key = "o7udtaekZzA0RnPs3E9lQiqeUqlRU2s8u+z/nVCJ"
  token      = "IQoJb3JpZ2luX2VjEHIaCXVzLXdlc3QtMiJHMEUCIGGKUTvwfbSR1M4KtZCEAJ62QTd6bh4PcsmBItqZ/kZXAiEAtk7p2NJR2Y9Pilic56mH9KmS7E3kra48I91z1aMM394quwIIOxAAGgwzNTUzMjc2ODA2NjciDAPgUEqtrB05xYok8SqYAuCrlXEkBl6k/j9sF9OhvLEUYLZhdXoEbUfAsTPSRFqXHPdzVMIQxVXCyQCkIIf8mVVleXNaQA6XGSIT/joPeOc5MaKwM77XvngJvjgkFCysIGel6CtaIpqFUR9xRUUA/yx3cztXB4KzSMvY3S0dB5fegHUp3Q3EipvExcpE899HkMQ8RTr696lASj+iIV249yEMCqwrvYTlFwPhJ78BkQVG2Eu2r4R0anXvFWHb/Ht89+IBDCRNj0jus6qDtvobtntD/uaBn1cTkO0Wf5UaxNCF1TBFGabtzrrgr3BbEvczEiv8wvTIxD7SELOtoz7kPdxb8STdMrlls0opAMiOA83hwK5+k9cEwKt3HfSLz/K7FmPR9o5GdDwwsq/sygY6nQECV60Gqs3mU2XhtaahidrVy6hZSk979iQn3ayv8D/s3RsSBzNDqMIC8dGeghWbgBqOfJ+0qizUfOg0HN62ytWiXUrPPOac+n8vQLUYTsJJFjZNr26kU1mLIBAdQwHVzX0YIzFHy0bfQ3CC1uJWVn6Mfk8qghx8vVUlr4G8QfHeaK9IhCiEkSW3jI35SXQrGiKWH7eN49t4zYkdWXba"
}