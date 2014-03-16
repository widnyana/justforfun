<?php
@error_reporting(1);

print "
 ***************************************************************
 * twitter username checker
 * released under ycl forum license 2012
 * coded by noisegate
 *
 ***************************************************************\n";
$used = 0;
$avail = 0;

$mode = getopt("f:");
if( !empty($mode['f']) ) {
    $file_handle = fopen($mode['f'], "r");
    while (!feof($file_handle)) {
        $line = fgets($file_handle);
        if ($line != "")
        {
            fuck(rtrim($line), $avail, $used);
        }

    }
    fclose($file_handle);
} else {
    if ( count($argv) > 1 )
    {
        for ($i = 1; $i < count($argv) ; $i++ )
        {
            fuck(rtrim($argv[$i]), $avail, $used);
        }
    } else {
        fuck(rtrim($argv[1]), $avail, $used);
    }
}
print "Tersedia: {$avail}\nTerpakai: {$used}\n";

function fuck($username='', &$avail, &$used) {
    $x = json_decode(file_get_contents("https://www.twitter.com/users/username_available?suggest=1&username={$username}&full_name=&email=&suggest_on_username=true&context=front&custom=1"));
    print "\t$username -> $x->msg\n"; if ( $x->reason == "taken") $used++; elseif ($x->reason == "available") $avail++;
}

?>
