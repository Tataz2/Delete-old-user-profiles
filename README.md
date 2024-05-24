# Delete-old-user-profiles
PowerShell script which deletes user profiles older than X days based on LocalProfileLoadTime and LocalProfileUnLoadTime IN WINDOWS REGISTRY

# - Gets a list of user profiles
# - Gets LocalProfileLoadTime and LocalProfileUnLoadTime for every profile
# - Tests if user is a domain user
# - Checks if username matches $ExcludeUsersList
# - Removes user profile from the list if not domain user, is exluded or if cannot get LocalProfileLoadTime and LocalProfileUnLoadTime
# - Tests if LocalProfileLoadTime and LocalProfileUnLoadTime are older than $MaxAgeInDays days.
# - Removes newer user profiles from the list
# - Deletes all user profiles which are still remaining and not filtered
