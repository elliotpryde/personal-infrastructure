resource "aws_iam_user" "nas-traefik" {
  name = "nas-traefik"
  path = "/nas/traefik/"
}

resource "aws_iam_access_key" "nas-traefik" {
  user = aws_iam_user.nas-traefik.name
}

# Allows my NAS Traefik instance to complete letsencrypt DNS challenges
resource "aws_iam_user_policy" "nas-traefik-letsencrypt" {
  name = "nas-traefik-letsencrypt"
  user = aws_iam_user.nas-traefik.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = ""
        Effect = "Allow"
        Action = [
          "route53:GetChange",
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets"
        ],
        Resource = [
          "arn:aws:route53:::hostedzone/*",
          "arn:aws:route53:::change/*"
        ]
      },
      {
        Sid      = ""
        Effect   = "Allow"
        Action   = "route53:ListHostedZonesByName"
        Resource = "*"
      }
    ]
  })
}
