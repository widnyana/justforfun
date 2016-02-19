<?php

$time = 169590;
$time2 = 1432264;
$time3 = 1432744;
$mul = 0.001;


function convert($seconds) {
    $seconds = ceil($seconds);
    //echo "<br /> -> ".$seconds . "\n<br />";
    
    $hours = floor($seconds / 3600);
    $mins = floor(($seconds - ($hours*3600)) / 60);
    $secs = floor($seconds % 60);
    
    return sprintf(
        "%s:%s:%s", 
        str_pad($hours, 2, 0), 
        str_pad($mins, 2, 0),
        str_pad($secs, 2, 0)
    );
}

echo " result -> " . convert($time * $mul);
echo "<br />result -> " . convert($time2 * $mul);
echo "<br />result -> " . convert($time3 * $mul);

echo "<br /> gmdate" . gmdate("H:i:s", ceil($time * $mul));
