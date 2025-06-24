#! /bin/bash
read -p "Enter an IP address :" ip

if [[ $ip =~ ^192.168.10.[0-9]{1,3}$ ]]; then
       echo "Head Office"
elif [[ $ip =~ ^192.168.20.[0-9]{1,3}$ ]]; then
       echo "Warehouse"
elif [[ $ip =~ ^192.168.21.[0-9]{1,3}$ ]]; then
	echo "Kandy Branch"
elif [[ $ip =~ ^192.168.22.[0-9]{1,3}$ ]]; then
	echo "Colombo Branch"
else
	echo "Invalid IP"
fi

#####################################################################E

#! /bin/bash

echo "Accessing text files..."

for file in file1.txt file2.txt file3.txt; do
    if [[ -f "$file" ]]; then
        echo "Displaying contents of $file:"
        cat "$file"
        echo "----------------------"
    else
        echo "$file not found."
    fi
done

echo "Finished processing files." 


